class Conversations::AutomationTransitionService
  Result = Struct.new(:status, :reason_code, :conversation, :transition, keyword_init: true)

  class Error < StandardError
    attr_reader :reason_code, :conversation

    def initialize(reason_code, conversation: nil)
      @reason_code = reason_code
      @conversation = conversation
      super(reason_code)
    end
  end

  class Conflict < Error; end
  class InvalidRequest < Error; end
  class FeatureDisabled < Error; end

  ACTION = 'send_to_human_queue'.freeze

  def initialize(account:, actor:, account_user:, conversation_display_id:, attributes:)
    @account = account
    @actor = actor
    @account_user = account_user
    @conversation_display_id = conversation_display_id
    @attributes = attributes.to_h.with_indifferent_access
  end

  def call
    validate_request!
    conversation = account.conversations.find_by!(display_id: conversation_display_id)

    conversation.with_lock { perform_locked_transition(conversation) }
  rescue Error
    raise
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    log_failure('persistence_error', conversation)
    raise InvalidRequest.new('transition_persistence_failed', conversation: conversation), cause: e
  end

  private

  attr_reader :account, :actor, :account_user, :conversation_display_id, :attributes

  def perform_locked_transition(conversation)
    authorize!(conversation)
    ensure_feature_enabled!(conversation)
    return idempotent_replay(conversation) if existing_transition(conversation)
    return already_in_queue(conversation) if projection(conversation).final?

    validate_last_message!(conversation)
    apply_transition!(conversation)
  end

  def validate_request!
    raise InvalidRequest, 'unsupported_action' unless attributes[:action] == ACTION
    raise InvalidRequest, 'invalid_idempotency_key' unless valid_idempotency_key?

    normalized_expected_last_message_id
  end

  def valid_idempotency_key?
    attributes[:idempotency_key].to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9._:-]{7,127}\z/)
  end

  def normalized_expected_last_message_id
    return @normalized_expected_last_message_id if defined?(@normalized_expected_last_message_id)
    return @normalized_expected_last_message_id = nil if attributes[:expected_last_message_id].blank?

    value = attributes[:expected_last_message_id]
    @normalized_expected_last_message_id = value.is_a?(Integer) ? value : Integer(value, 10)
  rescue ArgumentError, TypeError
    raise InvalidRequest, 'invalid_expected_last_message_id'
  end

  def authorize!(conversation)
    context = { user: actor, account: account, account_user: account_user }
    Pundit.authorize(context, conversation, :send_to_human_queue?)
  end

  def ensure_feature_enabled!(conversation)
    return if account.reload.feature_enabled?('conversation_send_to_human_queue')

    raise FeatureDisabled.new('feature_disabled', conversation: conversation)
  end

  def existing_transition(conversation)
    @existing_transition ||= conversation.automation_transitions.find_by(
      action: ACTION,
      idempotency_key: attributes[:idempotency_key]
    )
  end

  def idempotent_replay(conversation)
    Result.new(
      status: 'duplicate',
      reason_code: 'idempotency_replay',
      conversation: conversation,
      transition: existing_transition(conversation)
    )
  end

  def already_in_queue(conversation)
    Result.new(
      status: 'duplicate',
      reason_code: 'already_in_human_queue',
      conversation: conversation,
      transition: latest_completed_transition(conversation)
    )
  end

  def latest_completed_transition(conversation)
    conversation.automation_transitions.where(action: ACTION, status: 'completed').order(id: :desc).first
  end

  def validate_last_message!(conversation)
    return if normalized_expected_last_message_id.nil?
    return if normalized_expected_last_message_id == current_last_message_id(conversation)

    raise Conflict.new('stale_last_message', conversation: conversation)
  end

  def current_last_message_id(conversation)
    conversation.messages.where.not(message_type: :activity).reorder(nil).maximum(:id)
  end

  def apply_transition!(conversation)
    before_state = projection(conversation).snapshot
    projection(conversation).apply!
    transition = audit_recorder.record!(
      conversation: conversation,
      before_state: before_state,
      after_state: projection(conversation).snapshot
    )

    Result.new(
      status: 'accepted',
      reason_code: 'sent_to_human_queue',
      conversation: conversation,
      transition: transition
    )
  end

  def audit_recorder
    @audit_recorder ||= Conversations::AutomationTransitions::AuditRecorder.new(
      account: account,
      actor: actor,
      action: ACTION,
      attributes: {
        idempotency_key: attributes[:idempotency_key],
        expected_last_message_id: normalized_expected_last_message_id
      }
    )
  end

  def projection(conversation)
    @projection ||= Conversations::AutomationTransitions::HumanQueueProjection.new(conversation)
  end

  def log_failure(reason_code, conversation)
    Rails.logger.warn(
      event: 'conversation_automation_transition.failed',
      reason_code: reason_code,
      account_id: account.id,
      conversation_id: conversation&.id,
      action: ACTION
    )
  end
end

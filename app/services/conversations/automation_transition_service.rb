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

  delegate :action, :feature, :policy, :projection, :accepted_reason_code, :already_reason_code, to: :configuration

  def perform_locked_transition(conversation)
    authorize!(conversation)
    ensure_feature_enabled!(conversation)
    return idempotent_replay(conversation) if existing_transition(conversation)
    return already_projected(conversation) if projection_for(conversation).final?

    validate_concurrency!(conversation)
    validate_projection!(conversation)
    apply_transition!(conversation)
  end

  def validate_request!
    raise InvalidRequest, 'unsupported_action' unless configuration
    raise InvalidRequest, 'invalid_idempotency_key' unless valid_idempotency_key?
    validate_return_expectations!

    normalized_expected_last_message_id
    normalized_expected_assignee_id
  end

  def validate_return_expectations!
    return unless action == 'return_to_bia'
    raise InvalidRequest, 'expected_last_message_id_required' unless attributes.key?(:expected_last_message_id)
    raise InvalidRequest, 'expected_assignee_id_required' unless attributes.key?(:expected_assignee_id)
  end

  def configuration
    @configuration ||= Conversations::AutomationTransitions::ActionRegistry.fetch(attributes[:action])
  end

  def valid_idempotency_key?
    attributes[:idempotency_key].to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9._:-]{7,127}\z/)
  end

  def normalized_expected_last_message_id
    return @normalized_expected_last_message_id if defined?(@normalized_expected_last_message_id)
    return @normalized_expected_last_message_id = nil if attributes[:expected_last_message_id].blank?

    @normalized_expected_last_message_id = normalize_non_negative_integer(attributes[:expected_last_message_id])
  rescue ArgumentError, TypeError
    raise InvalidRequest, 'invalid_expected_last_message_id'
  end

  def normalized_expected_assignee_id
    return @normalized_expected_assignee_id if defined?(@normalized_expected_assignee_id)
    return @normalized_expected_assignee_id = :not_provided unless attributes.key?(:expected_assignee_id)
    return @normalized_expected_assignee_id = nil if attributes[:expected_assignee_id].blank?

    @normalized_expected_assignee_id = normalize_non_negative_integer(attributes[:expected_assignee_id])
  rescue ArgumentError, TypeError
    raise InvalidRequest, 'invalid_expected_assignee_id'
  end

  def normalize_non_negative_integer(value)
    normalized = value.is_a?(Integer) ? value : Integer(value, 10)
    raise ArgumentError if normalized.negative?

    normalized
  end

  def authorize!(conversation)
    context = { user: actor, account: account, account_user: account_user }
    Pundit.authorize(context, conversation, policy)
  end

  def ensure_feature_enabled!(conversation)
    return if account.reload.feature_enabled?(feature)

    raise FeatureDisabled.new('feature_disabled', conversation: conversation)
  end

  def existing_transition(conversation)
    @existing_transition ||= conversation.automation_transitions.find_by(
      action: action,
      idempotency_key: attributes[:idempotency_key]
    )
  end

  def idempotent_replay(conversation)
    build_result('duplicate', 'idempotency_replay', conversation, existing_transition(conversation))
  end

  def already_projected(conversation)
    build_result('duplicate', already_reason_code, conversation, latest_completed_transition(conversation))
  end

  def build_result(status, reason_code, conversation, transition)
    Result.new(status: status, reason_code: reason_code, conversation: conversation, transition: transition)
  end

  def latest_completed_transition(conversation)
    conversation.automation_transitions.where(action: action, status: 'completed').order(id: :desc).first
  end

  def validate_concurrency!(conversation)
    validate_last_message!(conversation)
    validate_assignee!(conversation)
  end

  def validate_last_message!(conversation)
    return if normalized_expected_last_message_id.nil?
    return if normalized_expected_last_message_id == current_last_message_id(conversation)

    raise Conflict.new('stale_last_message', conversation: conversation)
  end

  def validate_assignee!(conversation)
    return if normalized_expected_assignee_id == :not_provided
    return if normalized_expected_assignee_id == conversation.assignee_id

    raise Conflict.new('stale_assignee', conversation: conversation)
  end

  def current_last_message_id(conversation)
    conversation.messages.where.not(message_type: :activity).reorder(nil).maximum(:id)
  end

  def validate_projection!(conversation)
    projection_for(conversation).validate! if projection_for(conversation).respond_to?(:validate!)
  rescue Conversations::AutomationTransitions::BiaProjection::InvalidState => e
    raise Conflict.new(e.reason_code, conversation: conversation)
  end

  def apply_transition!(conversation)
    before_state = projection_for(conversation).snapshot
    projection_for(conversation).apply!
    transition = audit_recorder.record!(
      conversation: conversation,
      before_state: before_state,
      after_state: projection_for(conversation).snapshot
    )

    build_result('accepted', accepted_reason_code, conversation, transition)
  end

  def audit_recorder
    @audit_recorder ||= Conversations::AutomationTransitions::AuditRecorder.new(
      account: account,
      actor: actor,
      configuration: configuration,
      attributes: {
        idempotency_key: attributes[:idempotency_key],
        expected_last_message_id: normalized_expected_last_message_id,
        expected_assignee_id: normalized_expected_assignee_id == :not_provided ? nil : normalized_expected_assignee_id
      }
    )
  end

  def projection_for(conversation)
    @projection_instance ||= projection.new(conversation)
  end

  def log_failure(reason_code, conversation)
    Rails.logger.warn(
      event: 'conversation_automation_transition.failed',
      reason_code: reason_code,
      account_id: account.id,
      conversation_id: conversation&.id,
      action: action || attributes[:action].to_s
    )
  end
end

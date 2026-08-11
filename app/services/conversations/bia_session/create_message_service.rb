class Conversations::BiaSession::CreateMessageService
  Result = Struct.new(:status, :reason_code, :conversation, :operation, :message, keyword_init: true)

  class Error < Conversations::BiaSession::ResetContextService::Error; end
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
    conversation.with_lock { perform_locked(conversation) }
  rescue Conversations::BiaSession::SessionValidator::Conflict => e
    raise Conflict.new(e.reason_code, conversation: conversation)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    raise InvalidRequest.new('operation_persistence_failed', conversation: conversation), cause: e
  end

  private

  attr_reader :account, :actor, :account_user, :conversation_display_id, :attributes

  def perform_locked(conversation)
    authorize!(conversation)
    ensure_feature_enabled!(conversation)
    return replay(conversation) if existing_operation(conversation)

    validator = session_validator(conversation)
    validator.validate!(require_reset: false)
    message = build_message(conversation)
    operation = record_operation!(conversation, validator, message)
    Result.new(status: 'accepted', reason_code: 'message_created', conversation: conversation, operation: operation, message: message)
  end

  def build_message(conversation)
    Messages::MessageBuilder.new(
      actor,
      conversation,
      content: attributes[:content],
      content_type: 'text',
      message_type: 'outgoing',
      private: false,
      content_attributes: { bia_session_generation: expected_generation, bia_source_message_id: source_message_id }
    ).perform
  end

  def record_operation!(conversation, validator, message)
    snapshot = validator.snapshot
    conversation.bia_session_operations.create!(
      account: account,
      actor: actor.is_a?(User) ? actor : nil,
      source_message_id: source_message_id,
      result_message: message,
      operation: 'create_message',
      session_generation: expected_generation,
      idempotency_key: idempotency_key,
      status: 'completed',
      reason_code: 'message_created',
      before_state: snapshot,
      after_state: snapshot,
      completed_at: Time.current
    )
  end

  def replay(conversation)
    operation = existing_operation(conversation)
    validate_replay_identity!(operation, conversation)
    Result.new(
      status: 'duplicate', reason_code: 'idempotency_replay', conversation: conversation,
      operation: operation, message: operation.result_message
    )
  end

  def validate_request!
    raise InvalidRequest, 'invalid_idempotency_key' unless idempotency_key.match?(/\A[A-Za-z0-9][A-Za-z0-9._:-]{7,127}\z/)
    raise InvalidRequest, 'invalid_content_type' unless attributes[:content_type].blank? || attributes[:content_type] == 'text'
    raise InvalidRequest, 'private_message_not_allowed' if ActiveModel::Type::Boolean.new.cast(attributes[:private])
    raise InvalidRequest, 'invalid_content' if attributes[:content].blank? || attributes[:content].to_s.bytesize > 10_000

    expected_generation
    source_message_id
  end

  def expected_generation
    @expected_generation ||= normalize_non_negative_integer(attributes[:expected_generation])
  rescue ArgumentError, TypeError
    raise InvalidRequest, 'invalid_expected_generation'
  end

  def source_message_id
    @source_message_id ||= normalize_non_negative_integer(attributes[:source_message_id])
  rescue ArgumentError, TypeError
    raise InvalidRequest, 'invalid_source_message_id'
  end

  def normalize_non_negative_integer(value)
    normalized = value.is_a?(Integer) ? value : Integer(value.to_s, 10)
    raise ArgumentError if normalized.negative?

    normalized
  end

  def idempotency_key
    attributes[:idempotency_key].to_s
  end

  def existing_operation(conversation)
    @existing_operation ||= conversation.bia_session_operations.find_by(operation: 'create_message', idempotency_key: idempotency_key)
  end

  def validate_replay_identity!(operation, conversation)
    return if operation.session_generation == expected_generation && operation.source_message_id == source_message_id

    raise Conflict.new('idempotency_key_reused', conversation: conversation)
  end

  def session_validator(conversation)
    Conversations::BiaSession::SessionValidator.new(
      conversation: conversation,
      expected_generation: expected_generation,
      source_message_id: source_message_id
    )
  end

  def authorize!(conversation)
    Pundit.authorize({ user: actor, account: account, account_user: account_user }, conversation, :create_bia_session_message?)
  end

  def ensure_feature_enabled!(conversation)
    return if account.reload.feature_enabled?('conversation_return_to_bia')

    raise FeatureDisabled.new('feature_disabled', conversation: conversation)
  end
end

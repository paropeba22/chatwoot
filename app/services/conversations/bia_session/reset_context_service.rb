class Conversations::BiaSession::ResetContextService
  Result = Struct.new(:status, :reason_code, :conversation, :operation, keyword_init: true)

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

  def initialize(account:, actor:, account_user:, conversation_display_id:, attributes:, operation_writer: nil)
    @account = account
    @actor = actor
    @account_user = account_user
    @conversation_display_id = conversation_display_id
    @attributes = attributes.to_h.with_indifferent_access
    @operation_writer = operation_writer
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

  attr_reader :account, :actor, :account_user, :conversation_display_id, :attributes, :operation_writer

  def perform_locked(conversation)
    authorize!(conversation)
    ensure_feature_enabled!(conversation)
    return replay(conversation) if existing_operation(conversation)

    validator = session_validator(conversation)
    validator.validate!(require_reset: true)
    apply_reset!(conversation, validator)
  end

  def apply_reset!(conversation, validator)
    before_attributes = (conversation.custom_attributes || {}).deep_dup
    after_attributes = reset_profile.apply(
      attributes: before_attributes,
      generation: expected_generation,
      source_message_id: source_message_id,
      timestamp: Time.current
    )
    conversation.update!(custom_attributes: after_attributes)
    operation = record_operation!(conversation, validator, before_attributes, after_attributes)
    Result.new(status: 'accepted', reason_code: 'context_reset_applied', conversation: conversation, operation: operation)
  end

  def replay(conversation)
    operation = existing_operation(conversation)
    validate_replay_identity!(operation, conversation)
    Result.new(status: 'duplicate', reason_code: 'idempotency_replay', conversation: conversation, operation: operation)
  end

  def record_operation!(conversation, validator, before_attributes, after_attributes)
    operation_attributes = {
      account: account,
      actor: actor.is_a?(User) ? actor : nil,
      source_message_id: source_message_id,
      operation: 'reset_context',
      reset_profile: reset_profile.class::PROFILE,
      session_generation: expected_generation,
      idempotency_key: idempotency_key,
      status: 'completed',
      reason_code: 'context_reset_applied',
      before_state: validator.snapshot.merge(reset_required: true),
      after_state: validator.snapshot.merge(reset_required: false),
      attributes_size_before: serialized_size(before_attributes),
      attributes_size_after: serialized_size(after_attributes),
      completed_at: Time.current
    }
    return operation_writer.call(conversation, operation_attributes) if operation_writer

    conversation.bia_session_operations.create!(operation_attributes)
  end

  def validate_request!
    raise InvalidRequest, 'invalid_idempotency_key' unless idempotency_key.match?(/\A[A-Za-z0-9][A-Za-z0-9._:-]{7,127}\z/)
    raise InvalidRequest, 'invalid_reset_profile' unless attributes[:reset_profile] == reset_profile.class::PROFILE

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
    @existing_operation ||= conversation.bia_session_operations.find_by(operation: 'reset_context', idempotency_key: idempotency_key)
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

  def reset_profile
    @reset_profile ||= Conversations::BiaSession::ResetProfileV1.new
  end

  def authorize!(conversation)
    Pundit.authorize({ user: actor, account: account, account_user: account_user }, conversation, :reset_bia_session?)
  end

  def ensure_feature_enabled!(conversation)
    return if account.reload.feature_enabled?('conversation_return_to_bia')

    raise FeatureDisabled.new('feature_disabled', conversation: conversation)
  end

  def serialized_size(value)
    JSON.generate(value).bytesize
  end
end

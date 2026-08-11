class Conversations::BiaSession::SessionValidator
  BOT_LABEL = 'bot-bia'.freeze
  HUMAN_QUEUE_LABEL = 'aguardando-humano'.freeze

  class Conflict < StandardError
    attr_reader :reason_code

    def initialize(reason_code)
      @reason_code = reason_code
      super(reason_code)
    end
  end

  def initialize(conversation:, expected_generation:, source_message_id:)
    @conversation = conversation
    @expected_generation = expected_generation
    @source_message_id = source_message_id
  end

  def validate!(require_reset: nil)
    validate_conversation_state!
    validate_generation!
    validate_source_message!
    validate_reset_state!(require_reset)
    source_message
  end

  def snapshot
    attributes = conversation.custom_attributes || {}
    labels = conversation.label_list.to_a

    {
      generation: generation,
      state: attributes['bia_automation_state'],
      reset_required: attributes['bia_context_reset_required'] == true,
      resume_after: normalize_optional_integer(attributes['bia_resume_after_message_id']),
      human_assignee_present: conversation.assignee_id.present?,
      agent_bot_assignee_present: conversation.assignee_agent_bot_id.present?,
      bot_bia: labels.include?(BOT_LABEL),
      aguardando_humano: labels.include?(HUMAN_QUEUE_LABEL),
      status: conversation.status,
      current_last_message_id: latest_public_incoming_id
    }
  end

  private

  attr_reader :conversation, :expected_generation, :source_message_id

  def validate_conversation_state!
    attributes = conversation.custom_attributes || {}
    labels = conversation.label_list.to_a

    conflict!('conversation_not_open') unless conversation.open?
    validate_human_state!(attributes, labels)
    validate_bia_state!(attributes, labels)
  end

  def validate_human_state!(attributes, labels)
    conflict!('human_assignee_present') if conversation.assignee_id.present?
    conflict!('human_queue_active') if labels.include?(HUMAN_QUEUE_LABEL)
    conflict!('human_return_pending') if attributes['bia_retorno_humano_pendente'] == true
  end

  def validate_bia_state!(attributes, labels)
    conflict!('bia_label_missing') unless labels.include?(BOT_LABEL)
    conflict!('session_not_active') unless attributes['bia_automation_state'] == 'active'
  end

  def validate_generation!
    conflict!('stale_session_generation') unless generation == expected_generation
  end

  def validate_source_message!
    conflict!('source_message_not_incoming') unless source_message.incoming?
    conflict!('source_message_private') if source_message.private?
    conflict!('source_message_before_resume_boundary') unless source_message.id > resume_after_message_id
    conflict!('stale_source_message') unless source_message.id == latest_public_incoming_id
  end

  def validate_reset_state!(required)
    return if required.nil?

    reset_required = conversation.custom_attributes['bia_context_reset_required'] == true
    conflict!('context_reset_not_required') if required && !reset_required
    conflict!('context_reset_required') if !required && reset_required
  end

  def source_message
    @source_message ||= conversation.messages.find_by(id: source_message_id) || conflict!('source_message_not_found')
  end

  def generation
    @generation ||= normalize_non_negative_integer(conversation.custom_attributes['bia_session_generation'])
  rescue ArgumentError, TypeError
    conflict!('invalid_session_generation')
  end

  def resume_after_message_id
    normalize_optional_integer(conversation.custom_attributes['bia_resume_after_message_id']) || 0
  rescue ArgumentError, TypeError
    conflict!('invalid_resume_boundary')
  end

  def latest_public_incoming_id
    conversation.messages.incoming.where(private: false).reorder(nil).maximum(:id)
  end

  def normalize_non_negative_integer(value)
    normalized = value.is_a?(Integer) ? value : Integer(value.to_s, 10)
    raise ArgumentError if normalized.negative?

    normalized
  end

  def normalize_optional_integer(value)
    return if value.blank?

    normalize_non_negative_integer(value)
  end

  def conflict!(reason_code)
    raise Conflict, reason_code
  end
end

class Conversations::AutomationTransitions::BiaSession
  STATE_KEY = 'bia_automation_state'.freeze
  GENERATION_KEY = 'bia_session_generation'.freeze
  RETURNED_AT_KEY = 'bia_returned_at'.freeze
  RESUME_AFTER_KEY = 'bia_resume_after_message_id'.freeze
  RESET_REQUIRED_KEY = 'bia_context_reset_required'.freeze
  HUMAN_RETURN_PENDING_KEY = 'bia_retorno_humano_pendente'.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def pause
    @attributes = attributes.merge(
      STATE_KEY => 'paused_human',
      GENERATION_KEY => next_generation,
      HUMAN_RETURN_PENDING_KEY => true
    )
  end

  def activate(resume_after_message_id:)
    @attributes = attributes.merge(
      STATE_KEY => 'active',
      GENERATION_KEY => next_generation,
      RETURNED_AT_KEY => Time.current.iso8601,
      RESUME_AFTER_KEY => resume_after_message_id,
      RESET_REQUIRED_KEY => true,
      HUMAN_RETURN_PENDING_KEY => false
    )
  end

  def state
    attributes[STATE_KEY].to_s
  end

  def generation
    Integer(attributes[GENERATION_KEY] || 0, 10).clamp(0, 2_147_483_646)
  rescue ArgumentError, TypeError
    0
  end

  private

  attr_reader :conversation

  def attributes
    @attributes ||= (conversation.custom_attributes || {}).deep_dup
  end

  def next_generation
    generation + 1
  end
end

class Conversations::AutomationTransitions::BiaProjection
  BOT_LABEL = 'bot-bia'.freeze
  HUMAN_QUEUE_LABEL = 'aguardando-humano'.freeze

  class InvalidState < StandardError
    attr_reader :reason_code

    def initialize(reason_code)
      @reason_code = reason_code
      super(reason_code)
    end
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def validate!
    raise InvalidState, 'conversation_not_open' unless conversation.open?
    raise InvalidState, 'bia_inbox_incompatible' unless bia_eligible?
  end

  def apply!
    conversation.skip_auto_assignment = true
    conversation.assign_attributes(
      status: :open,
      assignee: nil,
      assignee_agent_bot: nil,
      waiting_since: nil,
      custom_attributes: session.activate(resume_after_message_id: resume_after_message_id)
    )
    conversation.label_list = projected_labels
    conversation.save!
  ensure
    conversation.skip_auto_assignment = false
  end

  def final?
    conversation.open? && assignment_clear? && labels_projected? && session_active?
  end

  def snapshot
    {
      status: conversation.status,
      human_assignee_present: conversation.assignee_id.present?,
      agent_bot_assignee_present: conversation.assignee_agent_bot_id.present?,
      bot_bia: labels.include?(BOT_LABEL),
      aguardando_humano: labels.include?(HUMAN_QUEUE_LABEL),
      bia_retorno_humano_pendente: conversation.custom_attributes['bia_retorno_humano_pendente'] == true,
      bia_automation_state: session.state.presence,
      bia_session_generation: session.generation,
      bia_context_reset_required: conversation.custom_attributes['bia_context_reset_required'] == true
    }
  end

  private

  attr_reader :conversation

  def labels
    conversation.label_list.to_a
  end

  def projected_labels
    (labels - [HUMAN_QUEUE_LABEL]).union([BOT_LABEL])
  end

  def assignment_clear?
    conversation.assignee_id.nil? && conversation.assignee_agent_bot_id.nil?
  end

  def labels_projected?
    labels.include?(BOT_LABEL) && labels.exclude?(HUMAN_QUEUE_LABEL)
  end

  def session_active?
    session.state == 'active' &&
      session.generation.positive? &&
      conversation.custom_attributes['bia_retorno_humano_pendente'] == false
  end

  def session
    @session ||= Conversations::AutomationTransitions::BiaSession.new(conversation)
  end

  def resume_after_message_id
    conversation.messages.where(private: false).where.not(message_type: :activity).reorder(nil).maximum(:id)
  end

  def bia_eligible?
    labels.intersect?([BOT_LABEL, HUMAN_QUEUE_LABEL]) ||
      conversation.custom_attributes['bia_retorno_humano_pendente'] == true ||
      session.state.present?
  end
end

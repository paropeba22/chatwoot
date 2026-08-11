class Conversations::AutomationTransitions::HumanQueueProjection
  BOT_LABEL = 'bot-bia'.freeze
  HUMAN_QUEUE_LABEL = 'aguardando-humano'.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def apply!
    conversation.skip_auto_assignment = true
    conversation.assign_attributes(
      status: :open,
      assignee: nil,
      assignee_agent_bot: nil,
      waiting_since: conversation.waiting_since || Time.current,
      custom_attributes: session.pause
    )
    conversation.label_list = projected_labels
    conversation.save!
  ensure
    conversation.skip_auto_assignment = false
  end

  def final?
    conversation.open? &&
      conversation.assignee_id.nil? &&
      conversation.assignee_agent_bot_id.nil? &&
      labels.exclude?(BOT_LABEL) &&
      labels.include?(HUMAN_QUEUE_LABEL) &&
      conversation.custom_attributes['bia_retorno_humano_pendente'] == true
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
      bia_session_generation: session.generation
    }
  end

  private

  attr_reader :conversation

  def labels
    conversation.label_list.to_a
  end

  def projected_labels
    (labels - [BOT_LABEL]).union([HUMAN_QUEUE_LABEL])
  end

  def session
    @session ||= Conversations::AutomationTransitions::BiaSession.new(conversation)
  end
end

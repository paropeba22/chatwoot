class Conversations::AutomationTransitions::AuditRecorder
  def initialize(account:, actor:, action:, attributes:)
    @account = account
    @actor = actor
    @action = action
    @attributes = attributes
  end

  def record!(conversation:, before_state:, after_state:)
    audit_message = create_private_note!(conversation)
    conversation.automation_transitions.create!(
      account: account,
      actor: actor,
      audit_message: audit_message,
      action: action,
      status: 'completed',
      reason_code: 'manual_agent_action',
      idempotency_key: attributes[:idempotency_key],
      expected_last_message_id: attributes[:expected_last_message_id],
      before_state: before_state,
      after_state: after_state,
      completed_at: Time.current
    )
  end

  private

  attr_reader :account, :actor, :action, :attributes

  def create_private_note!(conversation)
    Messages::MessageBuilder.new(
      actor,
      conversation,
      {
        content: I18n.t('conversations.activity.sent_to_human_queue', user_name: actor.name),
        message_type: 'outgoing',
        private: true,
        content_attributes: { automation_transition: action }
      }
    ).perform
  end
end

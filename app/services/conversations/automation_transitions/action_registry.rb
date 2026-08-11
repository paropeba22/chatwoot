class Conversations::AutomationTransitions::ActionRegistry
  Configuration = Data.define(
    :action,
    :feature,
    :policy,
    :projection,
    :accepted_reason_code,
    :already_reason_code,
    :activity_i18n_key
  )

  ACTIONS = {
    'send_to_human_queue' => Configuration.new(
      action: 'send_to_human_queue',
      feature: 'conversation_send_to_human_queue',
      policy: :send_to_human_queue?,
      projection: Conversations::AutomationTransitions::HumanQueueProjection,
      accepted_reason_code: 'sent_to_human_queue',
      already_reason_code: 'already_in_human_queue',
      activity_i18n_key: 'conversations.activity.sent_to_human_queue'
    ),
    'return_to_bia' => Configuration.new(
      action: 'return_to_bia',
      feature: 'conversation_return_to_bia',
      policy: :return_to_bia?,
      projection: Conversations::AutomationTransitions::BiaProjection,
      accepted_reason_code: 'returned_to_bia',
      already_reason_code: 'already_with_bia',
      activity_i18n_key: 'conversations.activity.returned_to_bia'
    )
  }.freeze

  def self.fetch(action)
    ACTIONS.fetch(action.to_s)
  rescue KeyError
    nil
  end
end

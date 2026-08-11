# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_automation_transition do
    account
    conversation { association :conversation, account: account }
    actor { association :user, account: account }
    action { 'send_to_human_queue' }
    status { 'completed' }
    reason_code { 'manual_agent_action' }
    idempotency_key { "queue-#{SecureRandom.uuid}" }
    before_state { {} }
    after_state { {} }
    completed_at { Time.current }
  end
end

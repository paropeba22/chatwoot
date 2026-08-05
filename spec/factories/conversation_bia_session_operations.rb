# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_bia_session_operation do
    conversation
    account { conversation.account }
    source_message { association :message, account: conversation.account, conversation: conversation, inbox: conversation.inbox }
    operation { 'reset_context' }
    reset_profile { 'bia_session_v1' }
    session_generation { 1 }
    idempotency_key { "bia-operation-#{SecureRandom.uuid}" }
    status { 'completed' }
    reason_code { 'context_reset_applied' }
    before_state { {} }
    after_state { {} }
    completed_at { Time.current }
  end
end

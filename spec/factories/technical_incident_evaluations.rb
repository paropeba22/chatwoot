FactoryBot.define do
  factory :technical_incident_evaluation do
    account
    conversation { association :conversation, account: account }
    agent_bot { association :agent_bot, account: account }
    sequence(:request_id) { |number| "request-#{number}" }
    sequence(:source_message_id) { |number| "source-#{number}" }
    contract_version { '1.0' }
    mode { 'shadow' }
    status { 'no_candidate' }
    classification { {} }
    candidate_snapshot { [] }
    sanitized_contracts { [] }
    selected_contract { {} }
    expires_at { 20.minutes.from_now }
  end
end

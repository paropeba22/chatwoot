FactoryBot.define do
  factory :technical_incident do
    account
    title { 'Instabilidade de internet' }
    incident_type { 'unplanned_outage' }
    status { 'draft' }
    severity { 'major' }
    priority { 50 }
    problem_types { ['internet_connectivity'] }
    affected_services { ['internet'] }
    customer_message { 'Identificamos uma instabilidade. Previsão: {{estimated_resolution_at}}.' }
    internal_note { 'Fixture anonimizada.' }
    action { 'message_and_handoff' }
    starts_at { Time.current }
    expires_at { 6.hours.from_now }
    estimated_resolution_at { 2.hours.from_now }

    trait :active do
      status { 'active' }
    end

    trait :monitoring do
      status { 'monitoring' }
    end
  end

  factory :technical_incident_scope_group do
    account
    technical_incident
    position { 0 }
  end

  factory :technical_incident_scope_criterion do
    account
    technical_incident_scope_group
    criterion_type { 'general' }
    operator { 'in' }
    values { [] }
  end
end

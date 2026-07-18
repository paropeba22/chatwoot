class CreateTechnicalIncidents < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :technical_incidents_enabled, :boolean, null: false, default: false

    create_table :technical_incidents do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :title, null: false, limit: 200
      t.string :incident_type, null: false
      t.string :status, null: false, default: 'draft'
      t.string :severity, null: false, default: 'minor'
      t.integer :priority, null: false, default: 50
      t.text :problem_types, array: true, null: false, default: []
      t.text :affected_services, array: true, null: false, default: []
      t.text :customer_message
      t.text :internal_note
      t.string :action, null: false, default: 'message_and_handoff'
      t.datetime :starts_at
      t.datetime :expires_at
      t.datetime :review_at
      t.datetime :estimated_resolution_at
      t.integer :notification_version, null: false, default: 1
      t.boolean :resend_on_next_contact, null: false, default: false
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0
      t.integer :conversation_links_count, null: false, default: 0
      t.timestamps
    end

    add_index :technical_incidents, [:account_id, :status, :starts_at, :expires_at],
              name: 'idx_technical_incidents_active_window'
    add_index :technical_incidents, [:account_id, :incident_type]
    add_index :technical_incidents, [:account_id, :archived_at]
    add_check_constraint :technical_incidents, 'priority BETWEEN 0 AND 100', name: 'technical_incidents_priority_range'
    add_check_constraint :technical_incidents, 'notification_version > 0', name: 'technical_incidents_notification_version_positive'
    add_check_constraint :technical_incidents,
                         "incident_type IN ('unplanned_outage','degradation','scheduled_maintenance','external_provider','company_application','other')",
                         name: 'technical_incidents_type_allowlist'
    add_check_constraint :technical_incidents,
                         "status IN ('draft','scheduled','active','monitoring','resolved','expired','cancelled')",
                         name: 'technical_incidents_status_allowlist'
    add_check_constraint :technical_incidents,
                         "severity IN ('informational','minor','major','critical')",
                         name: 'technical_incidents_severity_allowlist'
    add_check_constraint :technical_incidents,
                         "action IN ('message_and_handoff','message_only','handoff_only')",
                         name: 'technical_incidents_action_allowlist'
    add_check_constraint :technical_incidents,
                         "problem_types <@ ARRAY['internet_connectivity','physical_fiber','optical_alarm','dns','external_service'," \
                         "'company_application','iptv','telephony','other','unidentified']::text[]",
                         name: 'technical_incidents_problem_types_allowlist'
    add_check_constraint :technical_incidents,
                         "affected_services <@ ARRAY['internet','dns','google','youtube','grupo_telecom_app','iptv','telephony','other']::text[]",
                         name: 'technical_incidents_services_allowlist'

    create_table :technical_incident_scope_groups do |t|
      t.references :account, null: false, foreign_key: true
      t.references :technical_incident, null: false, foreign_key: { on_delete: :cascade },
                   index: { name: 'idx_ti_scope_groups_incident' }
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :technical_incident_scope_groups, [:technical_incident_id, :position],
              name: 'idx_ti_scope_groups_position'

    create_table :technical_incident_scope_criteria do |t|
      t.references :account, null: false, foreign_key: true
      t.references :technical_incident_scope_group, null: false, foreign_key: { on_delete: :cascade },
                   index: { name: 'idx_ti_scope_criteria_group' }
      t.string :criterion_type, null: false
      t.string :operator, null: false, default: 'in'
      t.jsonb :values, null: false, default: []
      t.timestamps
    end

    add_index :technical_incident_scope_criteria,
              [:technical_incident_scope_group_id, :criterion_type],
              unique: true,
              name: 'idx_ti_scope_criteria_unique_type'
    add_check_constraint :technical_incident_scope_criteria,
                         "criterion_type IN ('general','service_specific','contract_id','pop_id','postal_code','city_neighborhood','city_street')",
                         name: 'ti_scope_criteria_type_allowlist'
    add_check_constraint :technical_incident_scope_criteria,
                         "operator IN ('in')",
                         name: 'ti_scope_criteria_operator_allowlist'

    create_table :technical_incident_updates do |t|
      t.references :account, null: false, foreign_key: true
      t.references :technical_incident, null: false, foreign_key: true,
                   index: { name: 'idx_ti_updates_incident' }
      t.references :actor, polymorphic: true, index: { name: 'idx_ti_updates_actor' }
      t.string :origin, null: false
      t.string :action, null: false
      t.jsonb :changeset, null: false, default: {}
      t.string :request_id
      t.timestamps
    end

    add_index :technical_incident_updates, [:account_id, :created_at], name: 'idx_ti_updates_retention'

    create_table :technical_incident_evaluations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :technical_incident, foreign_key: true, index: { name: 'idx_ti_evaluations_incident' }
      t.references :agent_bot, foreign_key: true
      t.string :opaque_id, null: false
      t.string :request_id, null: false
      t.string :source_message_id
      t.string :contract_version, null: false, default: '1.0'
      t.string :mode, null: false
      t.string :status, null: false
      t.string :reason_code
      t.string :match_source
      t.decimal :operational_confidence, precision: 5, scale: 4
      t.jsonb :classification, null: false, default: {}
      t.jsonb :candidate_snapshot, null: false, default: []
      t.jsonb :sanitized_contracts, null: false, default: []
      t.jsonb :selected_contract, null: false, default: {}
      t.integer :latency_ms
      t.datetime :expires_at, null: false
      t.datetime :committed_at
      t.string :feedback
      t.text :feedback_note
      t.references :feedback_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :technical_incident_evaluations, :opaque_id, unique: true
    add_index :technical_incident_evaluations, [:account_id, :request_id], unique: true
    add_index :technical_incident_evaluations, [:account_id, :source_message_id],
              unique: true,
              where: 'source_message_id IS NOT NULL',
              name: 'idx_ti_evaluations_source_message'
    add_index :technical_incident_evaluations, [:account_id, :created_at], name: 'idx_ti_evaluations_retention'
    add_check_constraint :technical_incident_evaluations,
                         "mode IN ('shadow','active')",
                         name: 'ti_evaluations_mode_allowlist'
    add_check_constraint :technical_incident_evaluations,
                         "status IN ('no_candidate','general_match','localized_candidate','needs_document','needs_contract_selection'," \
                         "'matched','ambiguous','expired','fallback','stale','duplicate','accepted')",
                         name: 'ti_evaluations_status_allowlist'

    create_table :technical_incident_conversation_links do |t|
      t.references :account, null: false, foreign_key: true
      t.references :technical_incident, null: false, foreign_key: true,
                   index: { name: 'idx_ti_conversation_links_incident' }
      t.references :conversation, null: false, foreign_key: true
      t.references :technical_incident_evaluation, foreign_key: true,
                   index: { name: 'idx_ti_conversation_links_evaluation' }
      t.string :contract_reference, null: false, default: ''
      t.integer :notification_version, null: false
      t.timestamps
    end

    add_index :technical_incident_conversation_links,
              [:conversation_id, :technical_incident_id, :notification_version, :contract_reference],
              unique: true,
              name: 'idx_ti_conversation_links_idempotency'

    create_table :technical_incident_deliveries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :technical_incident, null: false, foreign_key: true,
                   index: { name: 'idx_ti_deliveries_incident' }
      t.references :technical_incident_evaluation, null: false, foreign_key: true,
                   index: { name: 'idx_ti_deliveries_evaluation' }
      t.references :technical_incident_conversation_link, foreign_key: true,
                   index: { name: 'idx_ti_deliveries_link' }
      t.references :conversation, null: false, foreign_key: true
      t.references :message, foreign_key: true
      t.string :idempotency_key, null: false
      t.string :delivery_kind, null: false, default: 'initial'
      t.string :state, null: false, default: 'reserved'
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :delivery_queued_at
      t.datetime :delivered_at
      t.datetime :handoff_completed_at
      t.timestamps
    end

    add_index :technical_incident_deliveries, :idempotency_key, unique: true
    add_index :technical_incident_deliveries, [:state, :updated_at], name: 'idx_ti_deliveries_retry'
    add_check_constraint :technical_incident_deliveries,
                         "state IN ('reserved','message_created','delivery_queued','delivered','handoff_completed','failed_retryable','failed_terminal')",
                         name: 'ti_deliveries_state_allowlist'
    add_check_constraint :technical_incident_deliveries,
                         "delivery_kind IN ('initial','update','reopening')",
                         name: 'ti_deliveries_kind_allowlist'
  end
end

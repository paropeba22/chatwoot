class CreateTechnicalIncidentAutomationRecords < ActiveRecord::Migration[7.0]
  def change
    create_evaluations
    add_evaluation_indexes
    add_evaluation_constraints
    create_conversation_links
    create_deliveries
    add_delivery_constraints
  end

  private

  def create_evaluations
    create_table :technical_incident_evaluations do |table|
      add_evaluation_references(table)
      add_evaluation_identity(table)
      add_evaluation_decision(table)
      add_evaluation_payloads(table)
      add_evaluation_feedback(table)
      table.timestamps
    end
  end

  def add_evaluation_references(table)
    table.references :account, null: false, foreign_key: true
    table.references :conversation, null: false, foreign_key: true
    table.references :technical_incident, foreign_key: true, index: { name: 'idx_ti_evaluations_incident' }
    table.references :agent_bot, foreign_key: true
  end

  def add_evaluation_identity(table)
    table.string :opaque_id, null: false
    table.string :request_id, null: false
    table.string :source_message_id
    table.string :contract_version, null: false, default: '1.0'
    table.string :mode, null: false
  end

  def add_evaluation_decision(table)
    table.string :status, null: false
    table.string :reason_code
    table.string :match_source
    table.decimal :operational_confidence, precision: 5, scale: 4
    table.integer :latency_ms
    table.datetime :expires_at, null: false
    table.datetime :committed_at
  end

  def add_evaluation_payloads(table)
    table.jsonb :classification, null: false, default: {}
    table.jsonb :candidate_snapshot, null: false, default: []
    table.jsonb :sanitized_contracts, null: false, default: []
    table.jsonb :selected_contract, null: false, default: {}
  end

  def add_evaluation_feedback(table)
    table.string :feedback
    table.text :feedback_note
    table.references :feedback_by, foreign_key: { to_table: :users }
  end

  def add_evaluation_indexes
    add_index :technical_incident_evaluations, :opaque_id, unique: true
    add_index :technical_incident_evaluations, %i[account_id request_id], unique: true
    add_index :technical_incident_evaluations, %i[account_id source_message_id],
              unique: true, where: 'source_message_id IS NOT NULL', name: 'idx_ti_evaluations_source_message'
    add_index :technical_incident_evaluations, %i[account_id created_at], name: 'idx_ti_evaluations_retention'
  end

  def add_evaluation_constraints
    add_check_constraint :technical_incident_evaluations, "mode IN ('shadow','active')",
                         name: 'ti_evaluations_mode_allowlist'
    add_check_constraint :technical_incident_evaluations, evaluation_status_constraint,
                         name: 'ti_evaluations_status_allowlist'
  end

  def evaluation_status_constraint
    "status IN ('no_candidate','general_match','localized_candidate','needs_document'," \
      "'needs_contract_selection','matched','ambiguous','expired','fallback','stale','duplicate','accepted')"
  end

  def create_conversation_links
    create_table :technical_incident_conversation_links do |table|
      add_link_references(table)
      table.string :contract_reference, null: false, default: ''
      table.integer :notification_version, null: false
      table.timestamps
    end
    add_index :technical_incident_conversation_links, link_identity_columns,
              unique: true, name: 'idx_ti_conversation_links_idempotency'
  end

  def add_link_references(table)
    table.references :account, null: false, foreign_key: true
    table.references :technical_incident, null: false, foreign_key: true,
                                          index: { name: 'idx_ti_conversation_links_incident' }
    table.references :conversation, null: false, foreign_key: true
    table.references :technical_incident_evaluation, foreign_key: true,
                                                     index: { name: 'idx_ti_conversation_links_evaluation' }
  end

  def link_identity_columns
    %i[conversation_id technical_incident_id notification_version contract_reference]
  end

  def create_deliveries
    create_table :technical_incident_deliveries do |table|
      add_delivery_references(table)
      add_delivery_state(table)
      add_delivery_timestamps(table)
      table.timestamps
    end
    add_index :technical_incident_deliveries, :idempotency_key, unique: true
    add_index :technical_incident_deliveries, %i[state updated_at], name: 'idx_ti_deliveries_retry'
  end

  def add_delivery_references(table)
    table.references :account, null: false, foreign_key: true
    table.references :technical_incident, null: false, foreign_key: true,
                                          index: { name: 'idx_ti_deliveries_incident' }
    table.references :technical_incident_evaluation, null: false, foreign_key: true,
                                                     index: { name: 'idx_ti_deliveries_evaluation' }
    table.references :technical_incident_conversation_link, foreign_key: true,
                                                            index: { name: 'idx_ti_deliveries_link' }
    table.references :conversation, null: false, foreign_key: true
    table.references :message, foreign_key: true
  end

  def add_delivery_state(table)
    table.string :idempotency_key, null: false
    table.string :delivery_kind, null: false, default: 'initial'
    table.string :state, null: false, default: 'reserved'
    table.integer :attempts, null: false, default: 0
    table.text :last_error
  end

  def add_delivery_timestamps(table)
    table.datetime :delivery_queued_at
    table.datetime :delivered_at
    table.datetime :handoff_completed_at
  end

  def add_delivery_constraints
    add_check_constraint :technical_incident_deliveries, delivery_state_constraint,
                         name: 'ti_deliveries_state_allowlist'
    add_check_constraint :technical_incident_deliveries, "delivery_kind IN ('initial','update','reopening')",
                         name: 'ti_deliveries_kind_allowlist'
  end

  def delivery_state_constraint
    "state IN ('reserved','message_created','delivery_queued','delivered','handoff_completed'," \
      "'failed_retryable','failed_terminal')"
  end
end

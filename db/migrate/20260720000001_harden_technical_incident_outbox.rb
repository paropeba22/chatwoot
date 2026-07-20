class HardenTechnicalIncidentOutbox < ActiveRecord::Migration[7.0]
  def change
    change_table :technical_incident_deliveries, bulk: true do |t|
      t.string :outbox_state, null: false, default: 'pending'
      t.string :message_state, null: false, default: 'pending'
      t.string :transport_state, null: false, default: 'pending'
      t.string :link_state, null: false, default: 'pending'
      t.string :label_state, null: false, default: 'pending'
      t.string :note_state, null: false, default: 'pending'
      t.string :handoff_state, null: false, default: 'pending'
      t.string :audit_state, null: false, default: 'pending'
      t.string :provider
      t.string :provider_reference
      t.string :lock_token
      t.string :last_error_code
      t.datetime :next_retry_at
      t.datetime :locked_at
      t.datetime :completed_at
    end

    add_check_constraint :technical_incident_deliveries,
                         "outbox_state IN ('pending','processing','retry','completed','failed_terminal')",
                         name: 'ti_deliveries_outbox_state_allowlist'
    add_check_constraint :technical_incident_deliveries,
                         "message_state IN ('pending','not_required','created','failed_retryable','failed_terminal')",
                         name: 'ti_deliveries_message_state_allowlist'
    add_check_constraint :technical_incident_deliveries,
                         "transport_state IN ('pending','not_required','queued','delivered','failed_retryable','failed_terminal')",
                         name: 'ti_deliveries_transport_state_allowlist'
    %w[link label note handoff audit].each do |dimension|
      add_check_constraint :technical_incident_deliveries,
                           "#{dimension}_state IN ('pending','not_required','completed','failed_retryable','failed_terminal')",
                           name: "ti_deliveries_#{dimension}_state_allowlist"
    end

    add_index :technical_incident_deliveries, [:outbox_state, :next_retry_at, :id],
              name: 'idx_ti_deliveries_outbox_ready'
    add_index :technical_incident_deliveries, [:outbox_state, :locked_at],
              name: 'idx_ti_deliveries_outbox_watchdog'
    add_index :technical_incident_deliveries, [:transport_state, :id],
              where: "transport_state = 'queued'",
              name: 'idx_ti_deliveries_transport_status'
    add_index :technical_incidents, [:status, :starts_at],
              where: 'archived_at IS NULL',
              name: 'idx_ti_lifecycle_scheduled'
    add_index :technical_incidents, [:status, :expires_at],
              where: 'archived_at IS NULL',
              name: 'idx_ti_lifecycle_expiration'
    add_index :technical_incidents, [:status, :review_at],
              where: 'archived_at IS NULL AND review_at IS NOT NULL',
              name: 'idx_ti_lifecycle_review'
    add_index :technical_incidents, [:status, :updated_at],
              where: "archived_at IS NULL AND status = 'active'",
              name: 'idx_ti_lifecycle_forgotten'
    add_index :technical_incident_updates, [:technical_incident_id, :created_at, :id],
              name: 'idx_ti_updates_incident_page'
    add_index :technical_incident_evaluations, [:technical_incident_id, :created_at, :id],
              name: 'idx_ti_evaluations_incident_page'
    add_index :technical_incident_conversation_links, [:technical_incident_id, :created_at, :id],
              name: 'idx_ti_links_incident_page'
    add_index :technical_incident_evaluations, :created_at, name: 'idx_ti_evaluations_global_retention'
    add_index :technical_incident_updates, :created_at, name: 'idx_ti_updates_global_retention'
    add_index :technical_incidents, :problem_types, using: :gin, name: 'idx_ti_problem_types_gin'
    add_index :technical_incidents, :affected_services, using: :gin, name: 'idx_ti_affected_services_gin'

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE technical_incident_deliveries
             SET outbox_state = 'failed_terminal',
                 last_error_code = 'legacy_delivery_requires_review',
                 completed_at = CURRENT_TIMESTAMP
           WHERE created_at < CURRENT_TIMESTAMP
        SQL
      end
    end
  end
end

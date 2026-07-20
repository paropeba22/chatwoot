class CreateTechnicalIncidents < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :technical_incidents_enabled, :boolean, null: false, default: false
    create_incidents
    add_incident_indexes
    add_incident_constraints
  end

  private

  def create_incidents
    create_table :technical_incidents do |table|
      add_incident_identity(table)
      add_incident_content(table)
      add_incident_timing(table)
      add_incident_audit(table)
      table.timestamps
    end
  end

  def add_incident_identity(table)
    table.references :account, null: false, foreign_key: true, index: true
    table.string :title, null: false, limit: 200
    table.string :incident_type, null: false
    table.string :status, null: false, default: 'draft'
    table.string :severity, null: false, default: 'minor'
    table.integer :priority, null: false, default: 50
  end

  def add_incident_content(table)
    table.text :problem_types, array: true, null: false, default: []
    table.text :affected_services, array: true, null: false, default: []
    table.text :customer_message
    table.text :internal_note
    table.string :action, null: false, default: 'message_and_handoff'
  end

  def add_incident_timing(table)
    table.datetime :starts_at
    table.datetime :expires_at
    table.datetime :review_at
    table.datetime :estimated_resolution_at
    table.integer :notification_version, null: false, default: 1
    table.boolean :resend_on_next_contact, null: false, default: false
  end

  def add_incident_audit(table)
    table.references :created_by, foreign_key: { to_table: :users }
    table.references :updated_by, foreign_key: { to_table: :users }
    table.references :resolved_by, foreign_key: { to_table: :users }
    table.datetime :resolved_at
    table.datetime :archived_at
    table.integer :lock_version, null: false, default: 0
    table.integer :conversation_links_count, null: false, default: 0
  end

  def add_incident_indexes
    add_index :technical_incidents, %i[account_id status starts_at expires_at],
              name: 'idx_technical_incidents_active_window'
    add_index :technical_incidents, %i[account_id incident_type]
    add_index :technical_incidents, %i[account_id archived_at]
  end

  def add_incident_constraints
    add_numeric_constraints
    add_taxonomy_constraints
    add_content_constraints
  end

  def add_numeric_constraints
    add_check_constraint :technical_incidents, 'priority BETWEEN 0 AND 100',
                         name: 'technical_incidents_priority_range'
    add_check_constraint :technical_incidents, 'notification_version > 0',
                         name: 'technical_incidents_notification_version_positive'
  end

  def add_taxonomy_constraints
    add_check_constraint :technical_incidents, incident_type_constraint,
                         name: 'technical_incidents_type_allowlist'
    add_check_constraint :technical_incidents, status_constraint,
                         name: 'technical_incidents_status_allowlist'
    add_check_constraint :technical_incidents, "severity IN ('informational','minor','major','critical')",
                         name: 'technical_incidents_severity_allowlist'
    add_check_constraint :technical_incidents, "action IN ('message_and_handoff','message_only','handoff_only')",
                         name: 'technical_incidents_action_allowlist'
  end

  def add_content_constraints
    add_check_constraint :technical_incidents, problem_types_constraint,
                         name: 'technical_incidents_problem_types_allowlist'
    add_check_constraint :technical_incidents, services_constraint,
                         name: 'technical_incidents_services_allowlist'
  end

  def incident_type_constraint
    "incident_type IN ('unplanned_outage','degradation','scheduled_maintenance'," \
      "'external_provider','company_application','other')"
  end

  def status_constraint
    "status IN ('draft','scheduled','active','monitoring','resolved','expired','cancelled')"
  end

  def problem_types_constraint
    "problem_types <@ ARRAY['internet_connectivity','physical_fiber','optical_alarm','dns','external_service'," \
      "'company_application','iptv','telephony','other','unidentified']::text[]"
  end

  def services_constraint
    "affected_services <@ ARRAY['internet','dns','google','youtube','grupo_telecom_app','iptv','telephony','other']::text[]"
  end
end

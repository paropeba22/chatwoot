class CreateTechnicalIncidentScopesAndUpdates < ActiveRecord::Migration[7.0]
  def change
    create_scope_groups
    create_scope_criteria
    add_scope_constraints
    create_updates
  end

  private

  def create_scope_groups
    create_table :technical_incident_scope_groups do |table|
      table.references :account, null: false, foreign_key: true
      table.references :technical_incident, null: false, foreign_key: { on_delete: :cascade },
                                            index: { name: 'idx_ti_scope_groups_incident' }
      table.integer :position, null: false, default: 0
      table.timestamps
    end
    add_index :technical_incident_scope_groups, %i[technical_incident_id position],
              name: 'idx_ti_scope_groups_position'
  end

  def create_scope_criteria
    create_table :technical_incident_scope_criteria do |table|
      table.references :account, null: false, foreign_key: true
      table.references :technical_incident_scope_group, null: false, foreign_key: { on_delete: :cascade },
                                                        index: { name: 'idx_ti_scope_criteria_group' }
      table.string :criterion_type, null: false
      table.string :operator, null: false, default: 'in'
      table.jsonb :values, null: false, default: []
      table.timestamps
    end
    add_index :technical_incident_scope_criteria, %i[technical_incident_scope_group_id criterion_type],
              unique: true, name: 'idx_ti_scope_criteria_unique_type'
  end

  def add_scope_constraints
    add_check_constraint :technical_incident_scope_criteria, scope_type_constraint,
                         name: 'ti_scope_criteria_type_allowlist'
    add_check_constraint :technical_incident_scope_criteria, "operator IN ('in')",
                         name: 'ti_scope_criteria_operator_allowlist'
  end

  def scope_type_constraint
    "criterion_type IN ('general','service_specific','contract_id','pop_id','postal_code'," \
      "'city_neighborhood','city_street')"
  end

  def create_updates
    create_table :technical_incident_updates do |table|
      table.references :account, null: false, foreign_key: true
      table.references :technical_incident, null: false, foreign_key: true,
                                            index: { name: 'idx_ti_updates_incident' }
      table.references :actor, polymorphic: true, index: { name: 'idx_ti_updates_actor' }
      table.string :origin, null: false
      table.string :action, null: false
      table.jsonb :changeset, null: false, default: {}
      table.string :request_id
      table.timestamps
    end
    add_index :technical_incident_updates, %i[account_id created_at], name: 'idx_ti_updates_retention'
  end
end

class CreateConversationInactivityShadowAssessments < ActiveRecord::Migration[7.0]
  def up
    add_column :accounts, :conversation_inactivity_shadow_enabled, :boolean, default: false, null: false
    create_assessment_table
    add_references
    add_indexes
    add_constraints
  end

  def down
    drop_table :conversation_inactivity_shadow_assessments
    remove_column :accounts, :conversation_inactivity_shadow_enabled
  end

  private

  def create_assessment_table
    create_table :conversation_inactivity_shadow_assessments do |table|
      table.integer :account_id, null: false
      table.integer :conversation_id, null: false
      table.string :classification, null: false
      table.string :reason_code, null: false
      table.string :operational_bucket
      table.integer :session_generation, null: false, default: 0
      table.integer :customer_wait_seconds
      table.integer :operation_wait_seconds
      table.decimal :confidence, precision: 4, scale: 3, null: false
      table.datetime :observed_at, null: false
      table.timestamps
    end
  end

  def add_references
    add_foreign_key :conversation_inactivity_shadow_assessments, :accounts, on_delete: :cascade
    add_foreign_key :conversation_inactivity_shadow_assessments, :conversations, on_delete: :cascade
  end

  def add_indexes
    add_index :conversation_inactivity_shadow_assessments, %i[account_id conversation_id],
              unique: true, name: 'idx_inactivity_shadow_account_conversation'
    add_index :conversation_inactivity_shadow_assessments, %i[account_id classification observed_at],
              name: 'idx_inactivity_shadow_reporting'
  end

  def add_constraints
    add_check_constraint :conversation_inactivity_shadow_assessments,
                         "classification IN ('waiting_customer', 'waiting_human', 'waiting_automation', " \
                         "'likely_completed', 'operation_pending', 'handoff_pending', " \
                         "'stale_inconsistent', 'do_not_touch', 'unknown')",
                         name: 'inactivity_shadow_classification_allowed'
    add_check_constraint :conversation_inactivity_shadow_assessments,
                         'confidence >= 0 AND confidence <= 1',
                         name: 'inactivity_shadow_confidence_range'
    add_check_constraint :conversation_inactivity_shadow_assessments,
                         'session_generation >= 0',
                         name: 'inactivity_shadow_generation_non_negative'
    add_check_constraint :conversation_inactivity_shadow_assessments,
                         '(customer_wait_seconds IS NULL OR customer_wait_seconds >= 0) AND ' \
                         '(operation_wait_seconds IS NULL OR operation_wait_seconds >= 0)',
                         name: 'inactivity_shadow_waits_non_negative'
  end
end

class CreateConversationAutomationTransitions < ActiveRecord::Migration[7.0]
  def change
    create_table :conversation_automation_transitions do |table|
      table.integer :account_id, null: false
      table.integer :conversation_id, null: false
      table.integer :actor_id
      table.integer :audit_message_id
      table.string :action, null: false
      table.string :status, null: false, default: 'completed'
      table.string :reason_code, null: false
      table.string :idempotency_key, null: false
      table.integer :expected_last_message_id
      table.jsonb :before_state, null: false, default: {}
      table.jsonb :after_state, null: false, default: {}
      table.datetime :completed_at, null: false
      table.timestamps
    end

    add_references
    add_indexes
    add_constraints
  end

  private

  def add_references
    add_foreign_key :conversation_automation_transitions, :accounts, on_delete: :cascade
    add_foreign_key :conversation_automation_transitions, :conversations, on_delete: :cascade
    add_foreign_key :conversation_automation_transitions, :users, column: :actor_id, on_delete: :nullify
    add_foreign_key :conversation_automation_transitions, :messages, column: :audit_message_id, on_delete: :nullify
  end

  def add_indexes
    add_index :conversation_automation_transitions, :conversation_id
    add_index :conversation_automation_transitions, :actor_id
    add_index :conversation_automation_transitions, :audit_message_id
    add_index :conversation_automation_transitions,
              %i[account_id conversation_id action idempotency_key],
              unique: true,
              name: 'idx_conversation_automation_transitions_idempotency'
    add_index :conversation_automation_transitions,
              %i[account_id conversation_id created_at],
              name: 'idx_conversation_automation_transitions_audit'
  end

  def add_constraints
    add_check_constraint :conversation_automation_transitions,
                         "action = 'send_to_human_queue'",
                         name: 'conversation_automation_transitions_action_allowlist'
    add_check_constraint :conversation_automation_transitions,
                         "status = 'completed'",
                         name: 'conversation_automation_transitions_status_allowlist'
  end
end

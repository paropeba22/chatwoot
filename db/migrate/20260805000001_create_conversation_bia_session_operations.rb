class CreateConversationBiaSessionOperations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversation_automation_transitions, :expected_session_generation, :integer

    create_table :conversation_bia_session_operations do |table|
      table.integer :account_id, null: false
      table.integer :conversation_id, null: false
      table.integer :actor_id
      table.integer :source_message_id, null: false
      table.integer :result_message_id
      table.string :operation, null: false
      table.string :reset_profile
      table.integer :session_generation, null: false
      table.string :idempotency_key, null: false
      table.string :status, null: false, default: 'completed'
      table.string :reason_code, null: false
      table.jsonb :before_state, null: false, default: {}
      table.jsonb :after_state, null: false, default: {}
      table.integer :attributes_size_before
      table.integer :attributes_size_after
      table.datetime :completed_at, null: false
      table.timestamps
    end

    add_foreign_keys
    add_indexes
    add_constraints
  end

  private

  def add_foreign_keys
    add_foreign_key :conversation_bia_session_operations, :accounts, on_delete: :cascade
    add_foreign_key :conversation_bia_session_operations, :conversations, on_delete: :cascade
    add_foreign_key :conversation_bia_session_operations, :users, column: :actor_id, on_delete: :nullify
    add_foreign_key :conversation_bia_session_operations, :messages, column: :source_message_id, on_delete: :cascade
    add_foreign_key :conversation_bia_session_operations, :messages, column: :result_message_id, on_delete: :nullify
  end

  def add_indexes
    add_index :conversation_bia_session_operations, :conversation_id
    add_index :conversation_bia_session_operations, :actor_id
    add_index :conversation_bia_session_operations, :source_message_id
    add_index :conversation_bia_session_operations, :result_message_id
    add_index :conversation_bia_session_operations,
              %i[account_id conversation_id operation idempotency_key],
              unique: true,
              name: 'idx_bia_session_operations_idempotency'
    add_index :conversation_bia_session_operations,
              %i[account_id conversation_id created_at],
              name: 'idx_bia_session_operations_audit'
  end

  def add_constraints
    add_check_constraint :conversation_bia_session_operations,
                         "operation IN ('reset_context', 'create_message')",
                         name: 'conversation_bia_session_operations_operation_allowlist'
    add_check_constraint :conversation_bia_session_operations,
                         "status = 'completed'",
                         name: 'conversation_bia_session_operations_status_allowlist'
    add_check_constraint :conversation_bia_session_operations,
                         'session_generation >= 0',
                         name: 'conversation_bia_session_operations_generation_non_negative'
    add_check_constraint :conversation_automation_transitions,
                         'expected_session_generation IS NULL OR expected_session_generation >= 0',
                         name: 'conversation_automation_transitions_expected_generation_non_negative'
  end
end

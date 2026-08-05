class AddReturnToBiaAutomationTransition < ActiveRecord::Migration[7.0]
  OLD_ACTION_CONSTRAINT = "action = 'send_to_human_queue'".freeze
  NEW_ACTION_CONSTRAINT = "action IN ('send_to_human_queue', 'return_to_bia')".freeze
  CONSTRAINT_NAME = 'conversation_automation_transitions_action_allowlist'.freeze

  def up
    add_column :accounts, :conversation_return_to_bia_enabled, :boolean, default: false, null: false
    add_column :conversation_automation_transitions, :expected_assignee_id, :integer
    replace_action_constraint(NEW_ACTION_CONSTRAINT)
  end

  def down
    replace_action_constraint(OLD_ACTION_CONSTRAINT)
    remove_column :conversation_automation_transitions, :expected_assignee_id
    remove_column :accounts, :conversation_return_to_bia_enabled
  end

  private

  def replace_action_constraint(expression)
    remove_check_constraint :conversation_automation_transitions, name: CONSTRAINT_NAME
    add_check_constraint :conversation_automation_transitions, expression, name: CONSTRAINT_NAME
  end
end

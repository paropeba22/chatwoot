class AddOperationalBucketsToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :conversation_operational_buckets_enabled, :boolean, default: false, null: false
  end
end

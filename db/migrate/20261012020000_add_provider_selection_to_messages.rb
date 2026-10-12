class AddProviderSelectionToMessages < ActiveRecord::Migration[8.1]
  def change
    # Existing history has no recorded selection; do not infer provenance from today's environment.
    add_column :messages, :provider, :string
    add_column :messages, :model_id, :string
  end
end

class AddTuningSettingsToGameImages < ActiveRecord::Migration[8.1]
  def change
    add_column :game_images, :tuning_settings, :json, default: {}, null: false
  end
end

class RemoveControllerProfiles < ActiveRecord::Migration[8.1]
  def change
    remove_reference :game_images, :controller_profile, foreign_key: true
    remove_column :game_images, :ps2_serial, :string
    remove_column :game_images, :ps2_crc, :string
    remove_column :game_images, :controls_exported_digest, :string
    remove_column :game_images, :controls_exported_at, :datetime

    drop_table :controller_profiles do |t|
      t.string :name, null: false
      t.json :bindings, null: false, default: {}
      t.timestamps
      t.index :name, unique: true
    end
  end
end

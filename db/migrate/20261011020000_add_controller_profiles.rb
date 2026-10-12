class AddControllerProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :controller_profiles do |t|
      t.string :name, null: false
      t.json :bindings, null: false, default: {}
      t.timestamps
    end
    add_index :controller_profiles, :name, unique: true

    add_reference :game_images, :controller_profile, null: true, foreign_key: true
    add_column :game_images, :ps2_serial, :string
    add_column :game_images, :ps2_crc, :string
    add_column :game_images, :controls_exported_digest, :string
    add_column :game_images, :controls_exported_at, :datetime
  end
end

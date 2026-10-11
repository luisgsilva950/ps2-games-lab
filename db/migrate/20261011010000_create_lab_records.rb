class CreateLabRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :game_images do |t|
      t.string :name, null: false
     t.string :storage_key, null: false
     t.string :status, null: false, default: "pending"
     t.bigint :byte_size
     t.string :sha256
     t.text :error
     t.string :launch_status, null: false, default: "not_configured"
     t.text :launch_error
     t.timestamps
    end
   add_index :game_images, :storage_key, unique: true
   create_table :messages do |t|
     t.references :game_image, null: false, foreign_key: true
    t.string :role, null: false
    t.text :content, null: false
    t.string :status, null: false, default: "complete"
    t.text :error
    t.timestamps
   end
  end
end

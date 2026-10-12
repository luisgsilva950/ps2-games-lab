# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_12_030000) do
  create_table "game_images", force: :cascade do |t|
    t.string "name", null: false
    t.string "storage_key", null: false
    t.string "status", default: "pending", null: false
    t.bigint "byte_size"
    t.string "sha256"
    t.text "error"
    t.string "launch_status", default: "not_configured", null: false
    t.text "launch_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "tuning_settings", default: {}, null: false
    t.index ["storage_key"], name: "index_game_images_on_storage_key", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.integer "game_image_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.string "status", default: "complete", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "model_id"
    t.index ["game_image_id"], name: "index_messages_on_game_image_id"
  end

  add_foreign_key "messages", "game_images"
end

require "digest"
class GameImage < ApplicationRecord
  has_many :messages, -> { order(:id) }, dependent: :destroy
 validates :name, :storage_key, presence: true
 validates :storage_key, format: { with: /\A[0-9a-f-]{36}\z/ }
 validates :status, inclusion: { in: %w[pending importing ready failed] }
 def self.storage_root
   Rails.root.join("storage", "game_images")
 end
 def managed_path
   storage_path("original.iso")
 end
 def incoming_path
   storage_path("incoming.iso")
 end
 def storage_path(filename)
   raise "Invalid storage identity" unless storage_key&.match?(/\A[0-9a-f-]{36}\z/)
  root = self.class.storage_root
  folder = root.join(storage_key)
  [ root, folder, folder.join(filename) ].each { |path| raise "Unsafe storage link" if File.symlink?(path) }
  folder.join(filename)
 end
 def ready?
   status == "ready"
 end
 def verify_original!
   raise "Image not ready" unless ready?
  stat = File.lstat(managed_path)
  raise "Unsafe original" unless stat.file? && stat.nlink == 1
  raise "Original image changed" unless stat.size == byte_size && Digest::SHA256.file(managed_path).hexdigest == sha256
  managed_path
 end
end

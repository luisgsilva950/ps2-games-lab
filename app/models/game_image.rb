require "digest"
require "fileutils"
class GameImage < ApplicationRecord
  has_many :messages, -> { order(:id) }, dependent: :destroy
 validates :name, :storage_key, presence: true
 UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
 validates :storage_key, format: { with: UUID_FORMAT }
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

 def stage_upload!(input)
   path = incoming_path
   FileUtils.mkdir_p(path.dirname, mode: 0o700)
   File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
     input.rewind
     IO.copy_stream(input, output)
   end
 end

 def import_original!
   created_destination = false
   source = incoming_path
   destination = managed_path
   File.open(source, File::RDONLY | File::NOFOLLOW) do |input|
     stat = input.stat
     raise "Import file unavailable" unless stat.file? && stat.nlink == 1
     input.seek(16 * 2048)
     raise "Not a supported ISO9660 disc image" unless input.read(7) == "\x01CD001\x01".b
     digest = Digest::SHA256.file(source).hexdigest
     input.rewind
     File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
       created_destination = true
       IO.copy_stream(input, output)
       output.flush
       output.fsync
     end
     raise "Import copy verification failed" unless Digest::SHA256.file(destination).hexdigest == digest
     File.chmod(0o444, destination)
     File.unlink(source)
     update!(byte_size: stat.size, sha256: digest, status: "ready", error: nil, launch_status: "launching")
   end
 rescue StandardError
   File.unlink(source) if source && File.file?(source) && !File.symlink?(source)
   File.unlink(destination) if created_destination
   raise
 end

 private

 def storage_path(filename)
   raise "Invalid storage identity" unless storage_key&.match?(UUID_FORMAT)
   raise "Invalid storage filename" unless %w[incoming.iso original.iso].include?(filename)
   root = self.class.storage_root
   folder = root.join(storage_key)
   path = folder.join(filename)
   [ root.parent, root, folder, path ].each { |entry| raise "Unsafe storage link" if File.symlink?(entry) }
   path
 end
end

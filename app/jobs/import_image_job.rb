require "digest"
class ImportImageJob < ApplicationJob
  queue_as :default
 def perform(id)
   created_destination = false
   image = GameImage.find(id)
   claimed = image.with_lock do
     next false unless image.status == "pending"
    image.update!(status: "importing")
    true
   end
   return unless claimed
   source = image.incoming_path
   raise "Import file unavailable" unless File.file?(source) && !File.symlink?(source) && File.stat(source).nlink == 1
   File.open(source, "rb") do |file|
     file.seek(16 * 2048)
    raise "Not a supported ISO9660 disc image" unless file.read(7) == "\x01CD001\x01".b
   end
   digest = Digest::SHA256.file(source).hexdigest
   size = File.size(source)
   destination = image.managed_path
   File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
     created_destination = true
    File.open(source, "rb") { |input| IO.copy_stream(input, output) }
    output.flush
    output.fsync
   end
   raise "Import copy verification failed" unless Digest::SHA256.file(destination).hexdigest == digest
   File.chmod(0o444, destination)
   File.unlink(source)
   image.update!(status: "ready", byte_size: size, sha256: digest, error: nil, launch_status: "launching")
   EmulatorLauncher.new.launch(image)
  rescue StandardError => error
    if image && !image.ready?
      image.update!(status: "failed", error: error.is_a?(RuntimeError) ? error.message : "Import failed. Check local storage and retry with a new import.")
     paths = [ image.incoming_path ]
     paths << destination if created_destination
     paths.each { |path| File.unlink(path) if File.file?(path) && !File.symlink?(path) }
    end
   Rails.logger.error("Import failed: #{error.class}")
 end
end

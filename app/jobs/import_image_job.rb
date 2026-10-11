class ImportImageJob < ApplicationJob
  queue_as :default
 def perform(id)
   image = GameImage.find(id)
   claimed = image.with_lock do
     next false unless image.status == "pending"
    image.update!(status: "importing")
    true
   end
   return unless claimed
   image.import_original!
   EmulatorLauncher.new.launch(image)
  rescue StandardError => error
    if image && !image.ready?
      image.update!(status: "failed", error: error.is_a?(RuntimeError) ? error.message : "Import failed. Check local storage and retry with a new import.")
    end
   Rails.logger.error("Import failed: #{error.class}")
 end
end

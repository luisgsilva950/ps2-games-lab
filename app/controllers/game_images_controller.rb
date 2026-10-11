class GameImagesController < ApplicationController
  def index
    @game_images = GameImage.order(created_at: :desc)
  end
 def show
   @game_image = GameImage.find(params[:id])
  @messages = @game_image.messages
 end
 def create
   upload = params[:image]
   unless upload.respond_to?(:original_filename) && File.extname(upload.original_filename).downcase == ".iso" && upload.size.positive?
     return render json: { error: "Choose an extracted .iso disc image. ZIP and 7z archives are not supported." }, status: :unprocessable_entity
   end
   image = GameImage.create!(name: File.basename(upload.original_filename.tr("\\", "/")), storage_key: SecureRandom.uuid)
   image.stage_upload!(upload.tempfile)
   ImportImageJob.perform_later(image.id)
   render json: { url: game_image_path(image) }, status: :accepted
  rescue StandardError => error
    image&.update!(status: "failed", error: "Unable to schedule this import. Check local storage and the job worker.")
   Rails.logger.error("Upload failed: #{error.class}")
   render json: { error: "Import could not be started. Check available disk space and the job worker." }, status: :unprocessable_entity
 end
end

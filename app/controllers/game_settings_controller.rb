class GameSettingsController < ApplicationController
  before_action :set_game_image

  def update
    @game_image.tuning_settings = tuning_settings_params
    unless @game_image.save
      return render "game_images/show", status: :unprocessable_entity
    end

    if params[:commit] == "save_and_launch"
      result = EmulatorLauncher.new.launch(@game_image)
      if result == :launched
        redirect_to game_image_path(@game_image), notice: "Settings saved. PCSX2 process started in a separate desktop window. Boot and gameplay have not been verified.", status: :see_other
      else
        redirect_to game_image_path(@game_image), alert: "Settings saved, but playback could not start. #{@game_image.launch_error}", status: :see_other
      end
    else
      redirect_to game_image_path(@game_image), notice: "Settings saved. They apply the next time you launch this game.", status: :see_other
    end
  end

  def destroy
    @game_image.update!(tuning_settings: {})
    redirect_to game_image_path(@game_image), notice: "Lab tuning reset to inherit PCSX2 settings. This does not change a running session.", status: :see_other
  end

  private

  def set_game_image
    @game_image = GameImage.find(params[:game_image_id])
  end

  def tuning_settings_params
    settings = params.require(:game_image)[:tuning_settings]
    unless settings.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest, "Tuning settings must be an object"
    end
    allowed_keys = GameImage::TUNING_OPTIONS.keys
    unless (settings.keys - allowed_keys).empty? && settings.values.all? { |value| value.is_a?(String) }
      raise ActionController::BadRequest, "Tuning settings must contain supported scalar options"
    end
    settings.permit(*allowed_keys).to_h
  end
end

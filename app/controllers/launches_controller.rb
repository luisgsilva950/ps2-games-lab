class LaunchesController < ApplicationController
  def create
    game_image = GameImage.find(params[:game_image_id])
    result = EmulatorLauncher.new.launch(game_image)
    if result == :launched
      redirect_to game_image_path(game_image), notice: "PCSX2 process started in a separate desktop window. Boot and gameplay have not been verified.", status: :see_other
    else
      redirect_to game_image_path(game_image), alert: game_image.launch_error, status: :see_other
    end
  end
end

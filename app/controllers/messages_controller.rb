class MessagesController < ApplicationController
  def create
    game_image = GameImage.find(params[:game_image_id])
    Message.submit!(game_image: game_image, content: params[:content], provider: params[:provider], model: params[:model])
    redirect_to game_image_path(game_image), status: :see_other
  rescue Message::SubmissionError => error
    redirect_to game_image_path(game_image), alert: error.message, status: :see_other
  end
end

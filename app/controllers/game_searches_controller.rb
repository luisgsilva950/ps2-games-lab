class GameSearchesController < ApplicationController
  def show
    @query = params[:q].is_a?(String) ? params[:q].strip : ""
    if @query.empty? || @query.length > 100
      @error = "Enter a game title between 1 and 100 characters."
      render :show, status: :unprocessable_entity
      return
    end
    @results = CoolromSearch.new.search(@query)
  rescue CoolromSearch::Unavailable
    @error = "CoolROM search is unavailable right now. Your library and ISO import still work. Try again later."
    render :show, status: :service_unavailable
  end
end

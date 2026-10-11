class GameEventsController < ApplicationController
  include ActionController::Live

  def show
    # Resolve before committing headers so unknown images return an ordinary 404.
    GameImage.find(params[:id])
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache, no-store"
    response.headers["X-Accel-Buffering"] = "no"
    events = ActionController::Live::SSE.new(response.stream, retry: 1500)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 25
    previous = nil
    loop do
      snapshot = ActiveRecord::Base.connection_pool.with_connection do
        image = GameImage.find(params[:id])
        messages = image.messages.to_a
        {
          html: render_to_string(partial: "game_images/messages", formats: [ :html ], locals: { messages: messages }),
          active: %w[pending importing].include?(image.status) || image.launch_status == "launching" || messages.any? { |message| message.status == "pending" },
          image_status: image.status,
          launch_status: image.launch_status
        }
      end
      if snapshot != previous
        events.write(snapshot, event: "update")
        previous = snapshot
      end
      break unless snapshot[:active]
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      # Release leased connections between samples; no DB transaction spans the SSE session.
      ActiveRecord::Base.connection_handler.clear_active_connections!
      sleep 0.2
    end
  rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
    # Disconnects do not cancel the durable background reply.
  ensure
    events&.close
  end
end

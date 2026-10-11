require "test_helper"
class GameEventsTest < ActionDispatch::IntegrationTest
  test "reconnecting to completed chat receives durable escaped content and terminal status" do
    image = GameImage.create!(name: "disc.iso", storage_key: SecureRandom.uuid, status: "ready")
    image.messages.create!(role: "assistant", status: "complete", content: "<script>alert('unsafe')</script>")
    2.times do
      get events_game_image_path(image), headers: { "Accept" => "text/event-stream" }
      assert_response :success
      assert_equal "text/event-stream", response.media_type
      assert_includes response.body, "event: update"
      payload = JSON.parse(response.body.lines.find { |line| line.start_with?("data: ") }.delete_prefix("data: "))
      assert_equal false, payload.fetch("active")
      assert_equal "ready", payload.fetch("image_status")
      assert_includes payload.fetch("html"), "&lt;script&gt;"
      assert_not_includes payload.fetch("html"), "<script>"
    end
  end
  test "unknown image returns not found rather than opening a stream" do
    get events_game_image_path(id: 999999999)
    assert_response :not_found
  end
end

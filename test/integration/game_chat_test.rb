require "test_helper"
require_relative "../support/model_endpoint"
class GameChatTest < ActionDispatch::IntegrationTest
  setup do
    @image = GameImage.create!(name: "disc.iso", storage_key: SecureRandom.uuid, status: "ready", byte_size: 40960, sha256: "a" * 64)
  end
 teardown { @endpoint&.close }
 def configure(status: 200)
   @endpoint = ModelEndpoint.new(status: status)
  ENV["OPENAI_API_BASE"] = @endpoint.base_url
  ENV["OPENAI_API_KEY"] = "api-key-secret"
  ENV["OPENAI_MODEL"] = "lab-model"
 end
 test "missing provider prevents persistence and queued replies" do
   assert_no_difference("Message.count") do
     assert_no_enqueued_jobs { post game_image_messages_path(@image), params: { content: "Can you change handling?" } }
   end
  assert_redirected_to game_image_path(@image)
 end
 test "pending reply blocks another prompt and completed conversation preserves ordered context" do
   configure
  post game_image_messages_path(@image), params: { content: "Can you change handling?" }
  assert_redirected_to game_image_path(@image)
  reply = @image.messages.pending.sole
  assert_no_difference("Message.count") { post game_image_messages_path(@image), params: { content: "Another prompt" } }
  ChatReplyJob.perform_now(reply.id)
  assert_equal "complete", reply.reload.status
  request = @endpoint.requests.pop
  assert_equal "/v1/chat/completions", request[:path]
  assert_equal "Can you change handling?", request[:body]["messages"].last["content"]
  ChatReplyJob.perform_now(reply.id)
  assert @endpoint.requests.empty?, "duplicate job must not call provider again"
  perform_enqueued_jobs do
    post game_image_messages_path(@image), params: { content: "What evidence is necessary?" }
  end
  history = @endpoint.requests.pop[:body]["messages"].select { |m| %w[user assistant].include?(m["role"]) }
  assert_equal %w[user assistant user], history.map { |m| m["role"] }
  assert_equal [ "Can you change handling?", reply.content, "What evidence is necessary?" ], history.map { |m| m["content"] }
  get game_image_path(@image)
  assert_response :success
  assert_select ".message", count: 4
 end
 test "provider failure is recorded without exposing provider secrets" do
   configure(status: 401)
  perform_enqueued_jobs { post game_image_messages_path(@image), params: { content: "Inspect handling" } }
  reply = @image.messages.where(role: "assistant").sole
  assert_equal "failed", reply.status
  assert_not_includes reply.error, "api-key-secret"
  assert_not_includes reply.error, "private-provider-detail"
  get game_image_path(@image)
  assert_response :success
  assert_not_includes response.body, "api-key-secret"
 end
 test "oversized prompt and not ready image are rejected before any messages" do
   configure
  assert_no_difference("Message.count") { post game_image_messages_path(@image), params: { content: "x" * 4001 } }
  @image.update!(status: "importing")
  assert_no_difference("Message.count") { post game_image_messages_path(@image), params: { content: "hello" } }
 end
end

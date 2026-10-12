require "test_helper"
require_relative "../support/model_endpoint"

class GameChatTest < ActionDispatch::IntegrationTest
  setup do
    @image = GameImage.create!(name: "disc.iso", storage_key: SecureRandom.uuid, status: "ready", byte_size: 40960, sha256: "a" * 64)
  end

  teardown { @endpoint&.close }

  def configure(provider: "openai", status: 200)
    @endpoint = ModelEndpoint.new(provider: provider, status: status)
    if provider == "gemini"
      ENV["GEMINI_API_BASE"] = @endpoint.base_url
      ENV["GEMINI_API_KEY"] = "gemini-key-secret"
      ENV["GEMINI_MODEL"] = "gemini-2.5-flash"
    else
      ENV["OPENAI_API_BASE"] = @endpoint.base_url
      ENV["OPENAI_API_KEY"] = "api-key-secret"
      ENV["OPENAI_MODEL"] = "lab-model"
    end
  end

  test "missing provider prevents persistence and queued replies" do
    assert_rejected(content: "Can you change handling?")
  end

  test "missing chosen Gemini key cannot fall back to configured OpenAI" do
    configure
    assert_rejected(content: "Inspect handling", provider: "gemini", model: "gemini-2.5-flash")
    follow_redirect!
    assert_includes response.body, "GEMINI_API_KEY"
    assert @endpoint.requests.empty?
  end

  test "missing chosen OpenAI key cannot fall back to configured Gemini" do
    configure(provider: "gemini")
    assert_rejected(content: "Inspect handling", provider: "openai", model: "lab-model")
    follow_redirect!
    assert_includes response.body, "OPENAI_API_KEY"
    assert @endpoint.requests.empty?
  end

  test "pending reply blocks another prompt and completed conversation preserves ordered context" do
    configure
    post game_image_messages_path(@image), params: { content: "Can you change handling?" }
    assert_redirected_to game_image_path(@image)
    reply = @image.messages.pending.sole
    assert_equal [ "openai", "lab-model" ], [ reply.provider, reply.model_id ]
    assert_rejected(content: "Another prompt")
    ChatReplyJob.perform_now(reply.id)
    assert_equal "complete", reply.reload.status, reply.error
    assert_equal ModelEndpoint::REPLY_PARTS.join, reply.content
    request = @endpoint.requests.pop
    assert_equal "/v1/chat/completions", request[:path]
    assert_equal "Bearer api-key-secret", request[:headers]["authorization"]
    assert_equal "Can you change handling?", request[:body]["messages"].last["content"]
    ChatReplyJob.perform_now(reply.id)
    assert @endpoint.requests.empty?, "duplicate job must not call provider again"
    perform_enqueued_jobs do
      post game_image_messages_path(@image), params: { content: "What evidence is necessary?" }
    end
    second_reply = @image.messages.where(role: "assistant").last
    assert_equal "complete", second_reply.status, second_reply.error
    history = @endpoint.requests.pop[:body]["messages"].select { |message| %w[user assistant].include?(message["role"]) }
    assert_equal %w[user assistant user], history.map { |message| message["role"] }
    assert_equal [ "Can you change handling?", reply.content, "What evidence is necessary?" ], history.map { |message| message["content"] }
    get game_image_path(@image)
    assert_response :success
    assert_select ".message", count: 4
  end

  test "native Gemini SSE uses the queued selection after environment defaults change and preserves context" do
    configure(provider: "gemini")
    ENV["CHAT_PROVIDER"] = "gemini"
    post game_image_messages_path(@image), params: { content: "Can you change handling?", model: "  gemini-2.5-flash  " }
    reply = @image.messages.pending.sole
    assert_equal [ "gemini", "gemini-2.5-flash" ], [ reply.provider, reply.model_id ]
    assert_nil @image.messages.where(role: "user").sole.provider
    assert_nil @image.messages.where(role: "user").sole.model_id
    ENV["CHAT_PROVIDER"] = "openai"
    ENV["GEMINI_MODEL"] = "changed-after-enqueue"
    ENV["OPENAI_MODEL"] = "different-vendor-model"
    ChatReplyJob.perform_now(reply.id)
    assert_equal "complete", reply.reload.status, reply.error
    assert_equal ModelEndpoint::REPLY_PARTS.join, reply.content
    assert_equal [ "gemini", "gemini-2.5-flash" ], [ reply.provider, reply.model_id ]
    request = @endpoint.requests.pop
    assert_equal "POST", request[:method]
    assert_equal "/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse", request[:path]
    assert_equal "gemini-key-secret", request[:headers]["x-goog-api-key"]
    assert_nil request[:headers]["authorization"]
    assert_includes request[:body].fetch("systemInstruction").fetch("parts").first.fetch("text"), "You do not have the ISO bytes"
    assert_equal "Can you change handling?", request[:body].fetch("contents").last.fetch("parts").first.fetch("text")
    ChatReplyJob.perform_now(reply.id)
    assert @endpoint.requests.empty?, "duplicate Gemini job must not call provider again"
    perform_enqueued_jobs do
      post game_image_messages_path(@image), params: { content: "What evidence is necessary?", provider: "gemini", model: "gemini-2.5-flash" }
    end
    second_reply = @image.messages.where(role: "assistant").last
    assert_equal "complete", second_reply.status, second_reply.error
    history = @endpoint.requests.pop[:body].fetch("contents")
    assert_equal %w[user model user], history.map { |message| message.fetch("role") }
    assert_equal [ "Can you change handling?", reply.content, "What evidence is necessary?" ], history.map { |message| message.fetch("parts").map { |part| part.fetch("text") }.join }
    get game_image_path(@image)
    assert_response :success
    assert_select ".message", count: 4
  end

  test "nil selections use defaults but blank unsupported and malformed parameters do not enqueue" do
    configure(provider: "gemini")
    ENV["CHAT_PROVIDER"] = "gemini"
    invalid = [
      { provider: "" }, { provider: "unsupported" }, { provider: [ "gemini" ] }, { provider: { selected: "gemini" } },
      { model: "" }, { model: "   " }, { model: [ "gemini-2.5-flash" ] }, { model: { id: "gemini-2.5-flash" } },
      { model: "x" * 201 }, { model: "gemini?api-key=secret" }, { model: "gemini model" },
      { content: [ "Inspect handling" ] }, { content: { prompt: "Inspect handling" } }
    ]
    invalid.each { |selection| assert_rejected(**{ content: "Inspect handling" }.merge(selection)) }
    assert @endpoint.requests.empty?
    assert_enqueued_with(job: ChatReplyJob) do
      reply = Message.submit!(game_image: @image, content: "Inspect handling", provider: nil, model: nil)
      assert_equal [ "gemini", "gemini-2.5-flash" ], [ reply.provider, reply.model_id ]
    end
  end

  test "OpenAI provider failure is recorded without exposing provider secrets" do
    assert_safe_provider_failure(provider: "openai", status: 401)
  end

  test "Gemini provider failure is recorded without exposing provider secrets" do
    assert_safe_provider_failure(provider: "gemini", status: 403)
  end

  test "queued reply fails if its selected key disappears rather than switching vendors" do
    configure(provider: "gemini")
    post game_image_messages_path(@image), params: { content: "Inspect handling", provider: "gemini", model: "gemini-2.5-flash" }
    reply = @image.messages.pending.sole
    ENV.delete("GEMINI_API_KEY")
    ENV["OPENAI_API_KEY"] = "api-key-secret"
    ENV["OPENAI_MODEL"] = "lab-model"
    ChatReplyJob.perform_now(reply.id)
    assert_equal "failed", reply.reload.status
    assert_includes reply.error, "GEMINI_API_KEY"
    assert @endpoint.requests.empty?
  end

  test "historical assistant provenance stays unknown and old pending replies fail safely" do
    configure
    historical = @image.messages.create!(role: "assistant", status: "complete", content: "Historical reply")
    assert_nil historical.provider
    assert_nil historical.model_id
    legacy = @image.messages.create!(role: "assistant", status: "failed", content: "")
    legacy.update_columns(status: "pending")
    ChatReplyJob.perform_now(legacy.id)
    assert_equal "failed", legacy.reload.status
    assert_includes legacy.error, "no recorded provider or model"
    assert_nil legacy.provider
    assert_nil legacy.model_id
    assert @endpoint.requests.empty?
  end

  test "pending assistant records require supported selection" do
    reply = @image.messages.build(role: "assistant", status: "pending", content: "")
    assert_not reply.valid?
    assert reply.errors[:provider].present?
    assert reply.errors[:model_id].present?
    reply.assign_attributes(provider: "unsupported", model_id: "bad model")
    assert_not reply.valid?
    reply.assign_attributes(provider: "gemini", model_id: "gemini-2.5-flash")
    assert reply.valid?
  end

  test "oversized prompt and not ready image are rejected before any messages" do
    configure
    assert_rejected(content: "x" * 4001)
    @image.update!(status: "importing")
    assert_rejected(content: "hello")
  end

  test "symlinked reply lock cannot create an outside file or call the provider" do
    configure
    post game_image_messages_path(@image), params: { content: "Inspect handling" }
    reply = @image.messages.pending.sole
    Dir.mktmpdir("lab-lock") do |directory|
      root = Pathname.new(directory)
      locks = root.join("tmp", "chat_reply_locks")
      FileUtils.mkdir_p(locks)
      outside = root.join("outside.lock")
      File.symlink(outside, locks.join("#{reply.id}.lock"))
      Rails.stub(:root, root) { ChatReplyJob.perform_now(reply.id) }
      assert_equal "failed", reply.reload.status
      assert_not File.exist?(outside)
      assert @endpoint.requests.empty?, "unsafe lock must prevent a provider request"
    end
  end

  private

  def assert_rejected(**params)
    assert_no_difference("Message.count") do
      assert_no_enqueued_jobs { post game_image_messages_path(@image), params: params }
    end
    assert_redirected_to game_image_path(@image)
  end

  def assert_safe_provider_failure(provider:, status:)
    configure(provider: provider, status: status)
    model = provider == "gemini" ? "gemini-2.5-flash" : "lab-model"
    perform_enqueued_jobs { post game_image_messages_path(@image), params: { content: "Inspect handling", provider: provider, model: model } }
    reply = @image.messages.where(role: "assistant").sole
    assert_equal "failed", reply.status
    assert_includes reply.error, "selected provider API key"
    get game_image_path(@image)
    assert_response :success
    %w[api-key-secret gemini-key-secret private-provider-detail].each do |secret|
      assert_not_includes reply.error, secret
      assert_not_includes response.body, secret
    end
    assert_not_includes reply.error, "OPENAI"
  end
end

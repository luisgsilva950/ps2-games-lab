require "test_helper"

class GameSearchTest < ActionDispatch::IntegrationTest
  def with_provider(body, response_class: Net::HTTPOK, chunks: nil)
    code = Net::HTTPResponse::CODE_TO_OBJ.key(response_class)
    response = response_class.new("1.1", code, "Fixture")
    response["content-type"] = "text/html"
    response.define_singleton_method(:read_body) { |&block| (chunks || [ body ]).each(&block) }
    http = Object.new
    http.define_singleton_method(:request) { |_request, &block| block.call(response) }
    Net::HTTP.stub(:start, ->(*, **, &block) { block.call(http) }) { yield }
  end

  test "only PS2 result links are exposed and provider text is escaped without importing images" do
    html = <<~HTML
      <table><tr><td><div class="header">ROM Search</div><b>5</b> results found
        <a href="/roms/ps2/123/Safe_Game.php">Safe &lt;script&gt;alert(1)&lt;/script&gt; Game</a>
        <a href="/roms/psx/124/Other_Game.php">Wrong system</a>
        <a href="https://evil.example/roms/ps2/125/Game.php">External host</a>
        <a href="javascript:alert(1)">Executable link</a>
        <a href="/download/123">Downloader</a>
      </td></tr></table>
      <aside><a href="/roms/ps2/999/Unrelated.php">Unrelated promotion</a></aside>
    HTML
    with_provider(html) do
      assert_no_difference("GameImage.count") { get game_search_path, params: { q: "Safe Game" } }
      assert_response :success
      assert_select ".search-results a", count: 1
      assert_select ".search-results a[href='https://coolrom.com/roms/ps2/123/Safe_Game.php'][target='_blank'][rel='noopener noreferrer']", text: "Safe <script>alert(1)</script> Game"
      assert_select "script", text: "alert(1)", count: 0
    end
  end

  test "zero results differs from an unavailable or changed provider page" do
    with_provider('<table><tr><td><div class="header">ROM Search</div>No results found for "unknown game".</td></tr></table>') do
      get game_search_path, params: { q: "unknown game" }
      assert_response :success
      assert_select ".search-feedback[role=status]"
      assert_select ".search-results", count: 0
    end
    [ "<html>Access denied</html>", '<table><tr><td><div class="header">ROM Search</div>Changed interface</td></tr></table>' ].each do |html|
      with_provider(html) do
        get game_search_path, params: { q: "game" }
        assert_response :service_unavailable
        assert_select "[role=alert]"
      end
    end
  end

  test "redirects and oversized streaming responses fail without producing result links" do
    with_provider("", response_class: Net::HTTPFound) do
      get game_search_path, params: { q: "game" }
      assert_response :service_unavailable
      assert_select ".search-results a", count: 0
    end
    with_provider("", chunks: [ "a" * CoolromSearch::MAX_BYTES, "overflow" ]) do
      get game_search_path, params: { q: "game" }
      assert_response :service_unavailable
      assert_select ".search-results a", count: 0
    end
  end

  test "invalid queries do not contact the external provider" do
    Net::HTTP.stub(:start, ->(*) { flunk "invalid query must not leave the lab" }) do
      [ " ", "x" * 101, { title: "game" } ].each do |query|
        get game_search_path, params: { q: query }
        assert_response :unprocessable_entity
        assert_select "[role=alert]"
      end
    end
  end
end

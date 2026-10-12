require "test_helper"

class GameSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @image = GameImage.create!(name: "disc.iso", storage_key: SecureRandom.uuid, status: "ready", byte_size: iso_bytes.bytesize, sha256: Digest::SHA256.hexdigest(iso_bytes))
    @other = GameImage.create!(name: "other.iso", storage_key: SecureRandom.uuid)
  end

  test "workspace prioritizes settings and keeps AI optional without provider configuration" do
    get game_image_path(@image)
    assert_response :success
    assert_select ".tuning-panel select", count: 5
    assert_select "details.conversation:not([open])", count: 1
    assert_select ".tuning-panel button[value=save]", text: "Save settings"
    assert_select ".tuning-panel button[value=save_and_launch][disabled]", count: 1
    assert_select "select#game_image_tuning_settings_resolution option[value='']", text: "Inherit PCSX2 settings"
    assert response.body.index("id=\"settings-heading\"") < response.body.index("id=\"conversation-heading\"")
  end

  test "saving all supported settings persists only on the selected image without launching or model jobs" do
    values = { resolution: "3x", renderer: "metal", filtering: "automatic", audio_sync: "timestretch", frame_limit: "enabled" }
    EmulatorLauncher.stub(:new, -> { flunk "Save must not launch" }) do
      assert_no_enqueued_jobs do
        patch game_image_settings_path(@image), params: { game_image: { tuning_settings: values, name: "ignored.iso", storage_key: "unsafe" }, commit: "save" }
      end
    end
    assert_response :see_other
    assert_equal values.stringify_keys, @image.reload.tuning_settings
    assert_equal "disc.iso", @image.name
    assert_empty @other.reload.tuning_settings
    follow_redirect!
    assert_select "select#game_image_tuning_settings_resolution option[selected][value='3x']", count: 1
    assert_select ".notice", text: /Settings saved/
  end

  test "every displayed enum can be persisted and empty choices inherit" do
    GameImage::TUNING_OPTIONS.each do |key, choices|
      choices.each do |_label, value|
        patch game_image_settings_path(@image), params: { game_image: { tuning_settings: { key => value } } }
        assert_response :see_other
        assert_equal({ key => value }, @image.reload.tuning_settings)
      end
    end
    patch game_image_settings_path(@image), params: { game_image: { tuning_settings: GameImage::TUNING_OPTIONS.keys.index_with { "" } } }
    assert_response :see_other
    assert_empty @image.reload.tuning_settings
  end

  test "unsupported values keys and nested choices cannot overwrite persisted settings or launch" do
    @image.update!(tuning_settings: { renderer: "metal" })
    invalid = [ { renderer: "shell-command" }, { audio_sync: "async" }, { arbitrary: "on" }, { resolution: [ "2x" ] }, { renderer: { command: "metal" } } ]
    EmulatorLauncher.stub(:new, -> { flunk "Invalid settings must not launch" }) do
      invalid.each do |settings|
        patch game_image_settings_path(@image), params: { game_image: { tuning_settings: settings }, commit: "save_and_launch" }
        malformed = settings.keys.any? { |key| !GameImage::TUNING_OPTIONS.key?(key.to_s) } || settings.values.any? { |value| !value.is_a?(String) }
        assert_response(malformed ? :bad_request : :unprocessable_entity)
        assert_select ".notice-error", text: /unsupported/ unless malformed
        assert_equal({ "renderer" => "metal" }, @image.reload.tuning_settings)
      end
    end
  end

  test "malformed settings objects are rejected without changing the image" do
    [ "not-an-object", [ "metal" ], nil ].each do |settings|
      patch game_image_settings_path(@image), params: { game_image: { tuning_settings: settings } }
      assert_response :bad_request
      assert_empty @image.reload.tuning_settings
    end
    @image.tuning_settings = [ "metal" ]
    assert_not @image.valid?
    assert_includes @image.errors[:tuning_settings], "must be a settings object"
  end

  test "save and launch persists settings before invoking current launcher" do
    calls = []
    launcher = Object.new
    launcher.define_singleton_method(:launch) do |image|
      calls << [ image.id, image.reload.tuning_settings ]
      :launched
    end
    EmulatorLauncher.stub(:new, launcher) do
      patch game_image_settings_path(@image), params: { game_image: { tuning_settings: { resolution: "2x" } }, commit: "save_and_launch" }
    end
    assert_response :see_other
    assert_equal [ [ @image.id, { "resolution" => "2x" } ] ], calls
    follow_redirect!
    assert_select ".notice", text: /Settings saved.*PCSX2 process started/
  end

  test "launch failure leaves saved settings and shows actionable failure separately" do
    patch game_image_settings_path(@image), params: { game_image: { tuning_settings: { renderer: "metal" } }, commit: "save_and_launch" }
    assert_response :see_other
    assert_equal({ "renderer" => "metal" }, @image.reload.tuning_settings)
    assert_equal "ready", @image.status
    follow_redirect!
    assert_select ".notice-error", text: /Settings saved, but playback could not start/
    assert_select ".error-text", text: /PCSX2_EXECUTABLE/
  end

  test "reset clears only lab tuning and does not launch or change original metadata" do
    @image.update!(tuning_settings: { resolution: "6x", frame_limit: "disabled" })
    before = @image.attributes.except("tuning_settings", "updated_at")
    EmulatorLauncher.stub(:new, -> { flunk "Reset must not launch" }) do
      delete game_image_settings_path(@image)
    end
    assert_response :see_other
    assert_empty @image.reload.tuning_settings
    assert_equal before, @image.attributes.except("tuning_settings", "updated_at")
    follow_redirect!
    assert_select ".notice", text: /reset to inherit/
  end

  test "settings remain available before import completes but launch control is disabled" do
    @image.update!(status: "importing")
    patch game_image_settings_path(@image), params: { game_image: { tuning_settings: { renderer: "auto" } } }
    assert_response :see_other
    assert_equal({ "renderer" => "auto" }, @image.reload.tuning_settings)
    follow_redirect!
    assert_select ".tuning-panel button[value=save_and_launch][disabled]", count: 1
  end

  test "unknown image settings return ordinary not found responses" do
    patch game_image_settings_path(id: -1, game_image_id: -1), params: { game_image: { tuning_settings: { renderer: "auto" } } }
    assert_response :not_found
    delete game_image_settings_path(game_image_id: -1)
    assert_response :not_found
  end
  test "saving and resetting tuning preserve exact original bytes and read-only permissions" do
    Dir.mktmpdir("lab-settings") do |folder|
      GameImage.stub(:storage_root, Pathname.new(folder).join("managed")) do
        FileUtils.mkdir_p(@image.managed_path.dirname)
        File.binwrite(@image.managed_path, iso_bytes)
        File.chmod(0o444, @image.managed_path)
        patch game_image_settings_path(@image), params: { game_image: { tuning_settings: { resolution: "2x" } } }
        assert_response :see_other
        delete game_image_settings_path(@image)
        assert_response :see_other
        assert_equal iso_bytes, File.binread(@image.managed_path)
        assert_equal @image.sha256, Digest::SHA256.file(@image.managed_path).hexdigest
        assert_equal 0o444, File.stat(@image.managed_path).mode & 0o777
      end
    end
  end
end

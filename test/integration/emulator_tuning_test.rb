require "test_helper"
require_relative "../support/ps2_iso_fixture"

class EmulatorTuningTest < ActionDispatch::IntegrationTest
  include Ps2IsoFixture

  setup do
    @root = Pathname.new(File.realpath(Dir.mktmpdir("lab-tuning")))
    @bios = @root.join("bios.bin")
    File.binwrite(@bios, "synthetic firmware fixture")
    ENV["PCSX2_EXECUTABLE"] = RbConfig.ruby
    ENV["PCSX2_BIOS_PATH"] = @bios.to_s
    @image = GameImage.create!(name: "tuning.iso", storage_key: SecureRandom.uuid, status: "ready", byte_size: ps2_iso_bytes.bytesize, sha256: Digest::SHA256.hexdigest(ps2_iso_bytes))
    @data_root = Rails.root.join("storage", "pcsx2", Digest::SHA256.hexdigest(@bios.to_s))
    @profile = @data_root.join("PCSX2")
    @settings = @profile.join("gamesettings", "SLUS-21355_#{format('%08X', fixture_crc)}.ini")
    @state = @settings.dirname.join(".lab-tuning-#{@settings.basename}.json")
  end

  teardown do
    FileUtils.remove_entry(@data_root) if @data_root.directory?
    FileUtils.remove_entry(@root)
  end

  def with_original(bytes = ps2_iso_bytes)
    GameImage.stub(:storage_root, @root.join("managed")) do
      FileUtils.mkdir_p(@image.managed_path.dirname)
      File.unlink(@image.managed_path) if @image.managed_path.exist?
      File.binwrite(@image.managed_path, bytes)
      File.chmod(0o444, @image.managed_path)
      yield
    end
  end

  def launch(tuning = nil)
    @image.update!(tuning_settings: tuning) if tuning
    Pcsx2GameSettings.stub(:ensure_stopped!, nil) do
      Process.stub(:spawn, ->(*arguments, **options) { @spawn_arguments = arguments; @spawn_options = options; 12_345 }) do
        Process.stub(:detach, ->(pid) { assert_equal 12_345, pid }) { post game_image_launch_path(@image) }
      end
    end
    assert_redirected_to game_image_path(@image)
  end

  test "bounded identification matches PCSX2 word XOR ignores trailing bytes and supports nested paths and ISO versions" do
    [ false, true ].each do |nested|
      with_original(ps2_iso_bytes(nested: nested)) do
        identity = Ps2DiscIdentity.read(@image.managed_path)
        assert_equal "SLUS-21355", identity.serial
        assert_equal fixture_crc, identity.crc
        assert_equal @settings.basename.to_s, identity.settings_filename
      end
    end
  end

  test "custom ELF names use PCSX2 CRC-only settings filename" do
    with_original(ps2_iso_bytes(boot_name: "GAME.ELF")) do
      assert_equal "#{format('%08X', fixture_crc)}.ini", Ps2DiscIdentity.read(@image.managed_path).settings_filename
    end
  end

  test "identification rejects malformed directory extents and oversized directory scans" do
    bytes = ps2_iso_bytes
    bytes[16 * 2048 + 156 + 2, 4] = [ 0xFFFFFFFF ].pack("V")
    with_original(bytes) { assert_raises(Ps2DiscIdentity::Error) { Ps2DiscIdentity.read(@image.managed_path) } }
    bytes = ps2_iso_bytes
    bytes[16 * 2048 + 156 + 10, 4] = [ 8 * 1024 * 1024 ].pack("V")
    with_original(bytes) { assert_raises(Ps2DiscIdentity::Error) { Ps2DiscIdentity.read(@image.managed_path) } }
  end

  test "launch writes exact versioned keys while preserving native controller profiles saves and ISO" do
    native = "# native game settings\r\n[EmuCore]\r\nInputProfileName = My DualSense\r\n[Pad1]\r\nCross = SDL-0/A\r\n[EmuCore/GS]\r\nupscale_multiplier = 2\r\nRenderer = 14\r\nUserHacks = false\r\n[SPU2/Output]\r\nSyncMode = Disabled\r\nStandardVolume = 85\r\n"
    FileUtils.mkdir_p(@settings.dirname)
    File.binwrite(@settings, native)
    protected_files = { "inputprofiles/My DualSense.ini" => "[Pad1]\nCross = SDL-0/A\n", "memcards/saved.ps2" => "save bytes", "gamesettings/OTHER_12345678.ini" => "[EmuCore/GS]\nRenderer = 12\n" }
    protected_files.each do |name, bytes|
      path = @profile.join(name)
      FileUtils.mkdir_p(path.dirname)
      File.binwrite(path, bytes)
    end
    with_original do
      launch({ "resolution" => "3x", "renderer" => "metal", "filtering" => "automatic", "audio_sync" => "timestretch", "frame_limit" => "disabled" })
      assert_equal "launched", @image.reload.launch_status
      assert_equal [ [ File.realpath(RbConfig.ruby), File.realpath(RbConfig.ruby) ], "-datapath", @data_root.to_s, "-batch", "-unlimited", "--", @image.managed_path.to_s ], @spawn_arguments
      assert_equal({ in: File::NULL, out: File::NULL, err: File::NULL }, @spawn_options)
      expected = native.sub("upscale_multiplier = 2\r\n", "upscale_multiplier = 3\n").sub("Renderer = 14\r\n", "Renderer = 17\n").sub("[SPU2/Output]", "filter = 2\n[SPU2/Output]").sub("SyncMode = Disabled\r\n", "SyncMode = TimeStretch\n")
      assert_equal expected, File.binread(@settings)
      assert_equal ps2_iso_bytes, File.binread(@image.managed_path)
      assert_equal 0o444, File.stat(@image.managed_path).mode & 0o777
      protected_files.each { |name, bytes| assert_equal bytes, File.binread(@profile.join(name)) }
      # Changing a managed override does not capture our own value as baseline.
      launch({ "resolution" => "4x", "renderer" => "software", "filtering" => "nearest", "audio_sync" => "none", "frame_limit" => "enabled" })
      refute_includes @spawn_arguments, "-unlimited"
      assert_includes File.binread(@settings), "Renderer = 13\n"
      launch({})
      assert_equal native, File.binread(@settings)
      refute @state.exist?
      protected_files.each { |name, bytes| assert_equal bytes, File.binread(@profile.join(name)) }
    end
  end

  test "untuned launch preserves a native per-game file byte for byte and creates no metadata" do
    FileUtils.mkdir_p(@settings.dirname)
    native = "[EmuCore/GS]\nRenderer = 12\n[EmuCore]\nInputProfileName = existing\n"
    File.binwrite(@settings, native)
    with_original do
      launch
      assert_equal "launched", @image.reload.launch_status
      assert_equal native, File.binread(@settings)
      refute @state.exist?
    end
  end

  test "legacy CRC-only native controller settings are tuned in place instead of being shadowed" do
    FileUtils.mkdir_p(@settings.dirname)
    legacy = @settings.dirname.join(format("%08X.ini", fixture_crc))
    File.binwrite(legacy, "[EmuCore]\nInputProfileName = Legacy DualSense\n")
    with_original { launch({ "resolution" => "2x" }) }
    refute @settings.exist?
    assert_includes File.binread(legacy), "InputProfileName = Legacy DualSense"
    assert_includes File.binread(legacy), "upscale_multiplier = 2"
  end

  test "unsafe settings and metadata links refuse launch without touching their targets" do
    FileUtils.mkdir_p(@settings.dirname)
    target = @root.join("outside.ini")
    native = "[Pad1]\nCross = SDL-0/A\n"
    File.binwrite(target, native)
    [ @settings, @state ].each do |unsafe|
      File.symlink(target, unsafe)
      with_original do
        launch({ "resolution" => "2x" })
        assert_equal "failed", @image.reload.launch_status
        assert_nil @spawn_arguments
        assert_equal native, File.binread(target)
      end
      File.unlink(unsafe)
    end
    File.link(target, @settings)
    with_original do
      launch({ "resolution" => "2x" })
      assert_equal "failed", @image.reload.launch_status
      assert_equal native, File.binread(target)
    end
  end

  test "unsupported tuning identification fails visibly before process startup" do
    bytes = iso_bytes
    @image.update!(byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    with_original(bytes) do
      launch({ "resolution" => "2x" })
      assert_equal "failed", @image.reload.launch_status
      assert_match "could not identify this ISO", @image.launch_error
      assert_nil @spawn_arguments
      assert_equal bytes, File.binread(@image.managed_path)
    end
  end

  test "running PCSX2 is refused before any native config changes without signaling the session" do
    FileUtils.mkdir_p(@settings.dirname)
    native = "[EmuCore]\nInputProfileName = My DualSense\n"
    File.binwrite(@settings, native)
    @image.update!(tuning_settings: { "resolution" => "2x" })
    status = Struct.new(:success?).new(true)
    with_original do
      Open3.stub(:capture2, [ "PCSX2\n", status ]) do
        Process.stub(:spawn, ->(*) { flunk "must not spawn another emulator" }) do
          Process.stub(:kill, ->(*) { flunk "must not signal existing emulator" }) { post game_image_launch_path(@image) }
        end
      end
      assert_equal "failed", @image.reload.launch_status
      assert_match "already running", @image.launch_error
      assert_equal native, File.binread(@settings)
      refute @state.exist?
      refute @profile.join("inis", "PCSX2.ini").exist?
    end
  end

  test "native folder redirection stays inside managed profile and symlink directories are refused" do
    FileUtils.mkdir_p(@profile.join("inis"))
    base = @profile.join("inis", "PCSX2.ini")
    File.binwrite(base, "[Folders]\nGameSettings = custom/settings\n")
    with_original do
      launch({ "filtering" => "bilinear" })
      assert_equal "launched", @image.reload.launch_status
      assert_includes File.binread(@profile.join("custom", "settings", @settings.basename)), "filter = 1"
      File.binwrite(base, "[Folders]\nGameSettings = ../outside\n")
      @spawn_arguments = nil
      launch({ "filtering" => "bilinear" })
      assert_equal "failed", @image.reload.launch_status
      assert_nil @spawn_arguments
      assert_match "outside the managed", @image.launch_error
      File.binwrite(base, "[Folders]\nGameSettings = gamesettings\n")
      File.symlink(@root, @settings.dirname)
      launch({ "filtering" => "bilinear" })
      assert_equal "failed", @image.reload.launch_status
      assert_match "unsafe symbolic link", @image.launch_error
    end
  end
  test "all advertised enums use the source-backed INI values and removed overrides inherit" do
    advertised = GameImage::TUNING_OPTIONS.transform_values { |options| options.map(&:last) }
    Pcsx2GameSettings::SETTINGS.each do |name, (_, key, values)|
      assert_equal values.keys.sort, advertised.fetch(name).sort
      with_original do
        values.each do |value, native|
          launch({ name => value })
          assert_equal "launched", @image.reload.launch_status
          assert_includes File.binread(@settings), "#{key} = #{native}\n"
        end
        launch({})
        refute_match(/^\s*#{Regexp.escape(key)}\s*=/, File.binread(@settings))
        refute @state.exist?
      end
    end
  end

  test "corrupt restoration metadata refuses launch before changing native settings" do
    FileUtils.mkdir_p(@settings.dirname)
    native = "[Pad1]\nCross = SDL-0/A\n"
    File.binwrite(@settings, native)
    [ "not JSON", JSON.generate({ "resolution" => [ "Cross = malicious\n" ] }) ].each do |metadata|
      File.binwrite(@state, metadata)
      with_original do
        launch({ "resolution" => "2x" })
        assert_equal "failed", @image.reload.launch_status
        assert_match "restoration metadata is invalid", @image.launch_error
        assert_nil @spawn_arguments
        assert_equal native, File.binread(@settings)
        assert_equal metadata, File.binread(@state)
      end
    end
  end

  test "a launch lock already held refuses competing launch before process startup" do
    FileUtils.mkdir_p(@data_root)
    File.open(@data_root.join(".lab-launch.lock"), "w") do |lock|
      lock.flock(File::LOCK_EX)
      with_original do
        launch({ "resolution" => "2x" })
        assert_equal "failed", @image.reload.launch_status
        assert_match "Another PCSX2 launch", @image.launch_error
        assert_nil @spawn_arguments
        refute @profile.exist?
      end
    end
  end
end

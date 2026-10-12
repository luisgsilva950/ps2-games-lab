require "test_helper"
class ImageLaunchTest < ActionDispatch::IntegrationTest
  setup do
    @root = Pathname.new(File.realpath(Dir.mktmpdir("lab-launch")))
   @image = GameImage.create!(name: "disc.iso", storage_key: SecureRandom.uuid, status: "ready", byte_size: iso_bytes.bytesize, sha256: Digest::SHA256.hexdigest(iso_bytes))
   @bios = @root.join("bios.bin")
   File.binwrite(@bios, "synthetic firmware fixture")
   ENV["PCSX2_EXECUTABLE"] = RbConfig.ruby
   ENV["PCSX2_BIOS_PATH"] = @bios.to_s
  end
 teardown do
   config = Rails.root.join("storage", "pcsx2", Digest::SHA256.hexdigest(@bios.to_s))
  FileUtils.remove_entry(config) if File.directory?(config)
  FileUtils.remove_entry(@root)
 end
 def with_original
   GameImage.stub(:storage_root, @root.join("managed")) do
     FileUtils.mkdir_p(@image.managed_path.dirname)
    File.binwrite(@image.managed_path, iso_bytes)
    yield
   end
 end
 test "mutated original is refused before a process starts" do
   with_original do
     File.binwrite(@image.managed_path, iso_bytes.sub("CD001", "XXXXX"))
    Process.stub(:spawn, ->(*) { flunk "must not launch changed original" }) { post game_image_launch_path(@image) }
    assert_redirected_to game_image_path(@image)
    assert_equal "failed", @image.reload.launch_status
    assert_equal iso_bytes.sub("CD001", "XXXXX"), File.binread(@image.managed_path)
   end
 end
 test "symlink and hardlink originals cannot launch" do
   with_original do
     original_path = @image.managed_path
    target = @root.join("outside.iso")
    File.binwrite(target, iso_bytes)
    File.unlink(original_path)
    File.symlink(target, original_path)
    Process.stub(:spawn, ->(*) { flunk "must not launch symlink" }) { post game_image_launch_path(@image) }
    assert_equal "failed", @image.reload.launch_status
    File.unlink(original_path)
    File.link(target, original_path)
    Process.stub(:spawn, ->(*) { flunk "must not launch hardlink" }) { post game_image_launch_path(@image) }
    assert_equal "failed", @image.reload.launch_status
    assert_equal iso_bytes, File.binread(target)
   end
 end
 test "missing settings are actionable and leave image ready" do
   ENV.delete("PCSX2_EXECUTABLE")
  with_original do
    post game_image_launch_path(@image)
   assert_equal "not_configured", @image.reload.launch_status
   assert_equal "ready", @image.status
   assert_equal @image.sha256, Digest::SHA256.file(@image.managed_path).hexdigest
  end
 end

 test "launch leaves native controller exports settings and saves entirely user controlled" do
   data_root = Rails.root.join("storage", "pcsx2", Digest::SHA256.hexdigest(@bios.to_s))
   native_root = data_root.join("PCSX2")
   native_files = {
     "inis/PCSX2.ini" => "[InputSources]\nSDL = true\n[Pad1]\nType = DualShock2\n",
     "inputprofiles/lab-controller-7.ini" => "[Pad1]\nCross = Keyboard/W\n",
     "inputprofiles/My DualSense.ini" => "[Pad1]\nCross = SDL-0/A\n",
     "gamesettings/SLUS-21355_60A42FF5.ini" => "[EmuCore]\nInputProfileName = lab-controller-7\n",
     "memcards/synthetic.ps2" => "synthetic saved bytes"
   }
   native_files.each do |relative_path, bytes|
     path = native_root.join(relative_path)
     FileUtils.mkdir_p(path.dirname)
     File.binwrite(path, bytes)
   end
   entries = Dir.glob("**/*", base: native_root).sort
   with_original do
     File.chmod(0o444, @image.managed_path)
     calls = []
     spawn = lambda do |*arguments, **options|
       calls << arguments
       executable = File.realpath(RbConfig.ruby)
       assert_equal [ [ executable, executable ], "-datapath", data_root.to_s, "-batch", "--", @image.managed_path.to_s ], arguments
       assert_equal({ in: File::NULL, out: File::NULL, err: File::NULL }, options)
       12_345
     end
     Process.stub(:spawn, spawn) do
       Process.stub(:detach, ->(pid) { assert_equal 12_345, pid }) { post game_image_launch_path(@image) }
     end
     assert_redirected_to game_image_path(@image)
     assert_equal 1, calls.size
     assert_equal "launched", @image.reload.launch_status
     assert_nil @image.launch_error
     assert_equal iso_bytes, File.binread(@image.managed_path)
     assert_equal 0o444, File.stat(@image.managed_path).mode & 0o777
   end
   assert_equal entries, Dir.glob("**/*", base: native_root).sort
   native_files.each { |relative_path, bytes| assert_equal bytes, File.binread(native_root.join(relative_path)) }
 end

 test "process startup failure preserves the ready original and reports launch failure" do
   with_original do
     Process.stub(:spawn, ->(*) { raise Errno::EACCES }) { post game_image_launch_path(@image) }
     assert_redirected_to game_image_path(@image)
     assert_equal "failed", @image.reload.launch_status
     assert_equal "ready", @image.status
     assert_match "PCSX2 could not be started", @image.launch_error
     assert_equal iso_bytes, File.binread(@image.managed_path)
   end
 end
end

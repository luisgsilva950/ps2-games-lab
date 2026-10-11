require "test_helper"
class ImageLaunchTest < ActionDispatch::IntegrationTest
  setup do
    @root = Pathname.new(Dir.mktmpdir("lab-launch"))
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
end

require "test_helper"
class ImageImportTest < ActionDispatch::IntegrationTest
  setup do
    @root = Pathname.new(Dir.mktmpdir("lab-test"))
   @source = @root.join("source.iso")
   File.binwrite(@source, iso_bytes)
  end
 teardown { FileUtils.remove_entry(@root) }

 test "upload becomes a read-only exact copy and duplicate job preserves it" do
   GameImage.stub(:storage_root, @root.join("managed")) do
     source_hash = Digest::SHA256.file(@source).hexdigest
    perform_enqueued_jobs do
      post game_images_path, params: { image: Rack::Test::UploadedFile.new(@source, "application/octet-stream") }, as: :multipart
    end
    assert_response :accepted
    image = GameImage.order(:id).last
    assert_equal "ready", image.status
    assert_equal source_hash, image.sha256
    assert_equal source_hash, Digest::SHA256.file(image.managed_path).hexdigest
    assert_equal source_hash, Digest::SHA256.file(@source).hexdigest
    assert_equal 0, File.stat(image.managed_path).mode & 0o222
    ImportImageJob.perform_now(image.id)
    assert_equal source_hash, Digest::SHA256.file(image.managed_path).hexdigest
    get JSON.parse(response.body).fetch("url")
    assert_response :success
    assert_select "form[action=?]", game_image_messages_path(image)
   end
 end

 test "archive rejected and false ISO fails without publishing original" do
   GameImage.stub(:storage_root, @root.join("managed")) do
     archive = @root.join("game.7z")
    File.binwrite(archive, "not an ISO")
    assert_no_difference("GameImage.count") { post game_images_path, params: { image: Rack::Test::UploadedFile.new(archive) } }
    assert_response :unprocessable_entity
    File.binwrite(@source, "not an ISO")
    perform_enqueued_jobs { post game_images_path, params: { image: Rack::Test::UploadedFile.new(@source) } }
    image = GameImage.order(:id).last
    assert_equal "failed", image.status
    assert_not File.exist?(image.managed_path)
    assert_equal "not an ISO", File.binread(@source)
   end
 end

 test "existing destination is never overwritten or deleted" do
   GameImage.stub(:storage_root, @root.join("managed")) do
     image = GameImage.create!(name: "disc.iso", storage_key: SecureRandom.uuid)
    FileUtils.mkdir_p(image.incoming_path.dirname)
    File.binwrite(image.incoming_path, iso_bytes)
    File.binwrite(image.managed_path, "existing original")
    ImportImageJob.perform_now(image.id)
    assert_equal "failed", image.reload.status
    assert_equal "existing original", File.binread(image.managed_path)
   end
 end

 test "upload refuses a symlinked storage parent without writing outside the lab" do
   outside = @root.join("outside")
   FileUtils.mkdir_p(outside)
   sentinel = outside.join("keep.txt")
   File.binwrite(sentinel, "preserve outside data")
   File.symlink(outside, @root.join("alias"))
   GameImage.stub(:storage_root, @root.join("alias", "managed")) do
     perform_enqueued_jobs { post game_images_path, params: { image: Rack::Test::UploadedFile.new(@source) } }
     assert_response :unprocessable_entity
     assert_equal "failed", GameImage.order(:id).last.status
     assert_not File.exist?(outside.join("managed"))
     assert_equal "preserve outside data", File.binread(sentinel)
   end
 end
end

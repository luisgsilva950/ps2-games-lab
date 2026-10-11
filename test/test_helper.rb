ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "tmpdir"
class ActiveSupport::TestCase
  include ActiveJob::TestHelper
 setup do
   @original_env = ENV.to_h.slice("PCSX2_EXECUTABLE", "PCSX2_BIOS_PATH", "OPENAI_API_BASE", "OPENAI_API_KEY", "OPENAI_MODEL")
  %w[PCSX2_EXECUTABLE PCSX2_BIOS_PATH OPENAI_API_BASE OPENAI_API_KEY OPENAI_MODEL].each { |key| ENV.delete(key) }
 end
 teardown do
   %w[PCSX2_EXECUTABLE PCSX2_BIOS_PATH OPENAI_API_BASE OPENAI_API_KEY OPENAI_MODEL].each { |key| ENV.delete(key) }
  @original_env.each { |key, value| ENV[key] = value }
 end
 def iso_bytes
   bytes = "\0".b * (20 * 2048)
  bytes[16 * 2048, 7] = "\x01CD001\x01".b
  bytes
 end
end

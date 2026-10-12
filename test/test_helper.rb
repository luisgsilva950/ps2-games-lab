ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "tmpdir"
class ActiveSupport::TestCase
  include ActiveJob::TestHelper
  ISOLATED_ENV_KEYS = %w[PCSX2_EXECUTABLE PCSX2_BIOS_PATH OPENAI_API_BASE OPENAI_API_KEY OPENAI_MODEL GEMINI_API_KEY GEMINI_API_BASE GEMINI_MODEL CHAT_PROVIDER].freeze

  setup do
    @original_env = ENV.to_h.slice(*ISOLATED_ENV_KEYS)
    ISOLATED_ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    ISOLATED_ENV_KEYS.each { |key| ENV.delete(key) }
    @original_env.each { |key, value| ENV[key] = value }
  end
 def iso_bytes
   bytes = "\0".b * (20 * 2048)
  bytes[16 * 2048, 7] = "\x01CD001\x01".b
  bytes
 end
end

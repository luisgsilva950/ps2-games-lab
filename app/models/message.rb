require "uri"

class Message < ApplicationRecord
  MAX_CONTENT_LENGTH = 4_000
  MAX_REPLY_LENGTH = 8_000
  MAX_CONTEXT_LENGTH = 24_000

  class SubmissionError < StandardError; end

  belongs_to :game_image

  validates :role, inclusion: { in: %w[user assistant] }
  validates :status, inclusion: { in: %w[pending complete failed] }
  validates :content, presence: true, if: -> { status == "complete" }
  validates :content, length: { maximum: MAX_CONTENT_LENGTH }, if: -> { role == "user" }
  validates :content, length: { maximum: MAX_REPLY_LENGTH }, if: -> { role == "assistant" }

  scope :complete, -> { where(status: "complete") }
  scope :pending, -> { where(status: "pending") }

  def self.configuration_error
    missing = %w[OPENAI_API_KEY OPENAI_MODEL].select { |key| ENV[key].blank? }
    return "Chat is not configured. Set #{missing.join(' and ')} and restart Rails." if missing.any?

    uri = URI.parse(ENV.fetch("OPENAI_API_BASE", "https://api.openai.com/v1"))
    unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      "OPENAI_API_BASE must be an HTTP(S) API base URL without credentials, query, or fragment."
    end
  rescue URI::InvalidURIError
    "OPENAI_API_BASE must be a valid HTTP(S) API base URL."
  end

  def self.submit!(game_image:, content:)
    setup_error = configuration_error
    raise SubmissionError, setup_error if setup_error
    text = content.to_s.strip
    raise SubmissionError, "Enter a message." if text.blank?
    raise SubmissionError, "Messages must be #{MAX_CONTENT_LENGTH} characters or fewer." if text.length > MAX_CONTENT_LENGTH

    reply = nil
    game_image.with_lock do
      raise SubmissionError, "Wait until the image import is ready before chatting." unless game_image.ready?
      raise SubmissionError, "Wait for the pending reply before sending another message." if game_image.messages.pending.exists?

      context_length = game_image.messages.complete.pluck(:content).sum { |value| value.to_s.length }
      if context_length + text.length > MAX_CONTEXT_LENGTH
        raise SubmissionError, "This conversation has reached its context limit; no additional message was sent."
      end

      game_image.messages.create!(role: "user", content: text, status: "complete")
      reply = game_image.messages.create!(role: "assistant", content: "", status: "pending")
    end

    begin
      job = ChatReplyJob.perform_later(reply.id)
      raise SubmissionError, "Chat could not be queued. Check the job worker and try again." unless job
    rescue StandardError
      reply.update!(status: "failed", error: "Chat could not be queued. Check the job worker and try again.")
      raise SubmissionError, reply.error
    end
    reply
  end
end

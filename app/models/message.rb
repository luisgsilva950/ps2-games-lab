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
  validates :provider, inclusion: { in: ChatProvider::LABELS.keys }, if: -> { role == "assistant" && status == "pending" }
  validates :model_id, format: { with: /\A[a-zA-Z0-9][a-zA-Z0-9._:\/-]{0,199}\z/ }, if: -> { role == "assistant" && status == "pending" }

  scope :complete, -> { where(status: "complete") }
  scope :pending, -> { where(status: "pending") }

  def self.submit!(game_image:, content:, provider: nil, model: nil)
    provider = ChatProvider.default if provider.nil?
    unless provider.is_a?(String) && ChatProvider::LABELS.key?(provider)
      raise SubmissionError, "Choose a supported chat provider: OpenAI or Gemini."
    end
    model = ChatProvider.default_model(provider) if model.nil?
    raise SubmissionError, "Enter a model ID for the selected provider." unless model.is_a?(String)
    model = model.strip
    setup_error = ChatProvider.configuration_error(provider: provider, model: model)
    raise SubmissionError, setup_error if setup_error
    raise SubmissionError, "Enter a message." unless content.is_a?(String)
    text = content.strip
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
      reply = game_image.messages.create!(role: "assistant", content: "", status: "pending", provider: provider, model_id: model)
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

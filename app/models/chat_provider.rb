require "uri"

class ChatProvider
  LABELS = { "openai" => "OpenAI / compatible", "gemini" => "Google Gemini" }.freeze

  def self.default
    ENV.fetch("CHAT_PROVIDER", "openai")
  end

  def self.default_model(provider)
    case provider
    when "openai" then ENV["OPENAI_MODEL"].to_s
    when "gemini" then ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash")
    else ""
    end
  end

  def self.configuration_error(provider:, model:)
    return "Choose a supported chat provider: OpenAI or Gemini." unless LABELS.key?(provider)
    key = provider == "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY"
    return "Chat is not configured for #{LABELS.fetch(provider)}. Set #{key} and restart Rails and the worker." if ENV[key].blank?
    unless model.is_a?(String) && model.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._:\/-]{0,199}\z/)
      return "Enter a model ID of at most 200 characters for the selected provider."
    end

    variable = provider == "gemini" ? "GEMINI_API_BASE" : "OPENAI_API_BASE"
    uri = URI.parse(api_base(provider))
    unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      "#{variable} must be an HTTP(S) API base URL without credentials, query, or fragment."
    end
  rescue URI::InvalidURIError
    "#{variable} must be a valid HTTP(S) API base URL."
  end

  def self.configured?(provider)
    configuration_error(provider: provider, model: default_model(provider)).nil?
  end

  def self.api_base(provider)
    if provider == "gemini"
      ENV.fetch("GEMINI_API_BASE", "https://generativelanguage.googleapis.com/v1beta")
    else
      ENV.fetch("OPENAI_API_BASE", "https://api.openai.com/v1")
    end
  end

  def self.chat(provider:, model:)
    # RubyLLM's global logger can otherwise expose provider payloads and credentials.
    RubyLLM.logger.level = Logger::FATAL
    context = RubyLLM.context do |config|
      if provider == "gemini"
        config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
        config.gemini_api_base = api_base(provider)
      else
        config.openai_api_key = ENV.fetch("OPENAI_API_KEY")
        config.openai_api_base = api_base(provider)
      end
      config.request_timeout = 60
      config.max_retries = 0
    end
    protocol = provider == "gemini" ? :gemini : :chat_completions
    context.chat(model: model, provider: provider.to_sym, protocol: protocol, assume_model_exists: true)
  end
end

Rails.application.config.active_job.queue_adapter = :solid_queue unless Rails.env.test?
Rails.application.config.solid_queue.connects_to = { database: { writing: :queue } } unless Rails.env.test?
Rails.application.config.filter_parameters += %i[api_key openai_api_key gemini_api_key content]

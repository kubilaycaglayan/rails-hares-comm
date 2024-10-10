Rails.application.reloader.to_prepare do
  AMQPService = AmqpService.instance
end

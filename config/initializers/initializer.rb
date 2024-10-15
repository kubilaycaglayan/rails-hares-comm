Rails.application.reloader.to_prepare do

  # Init only in production
  unless Rails.const_defined?('Console')
    AMQPConnection = AmqpConnection.instance
    AMQPExchange = AmqpExchange.instance
    MSEmulator = MicroserviceEmulator.instance
  end
end

require 'bunny'

class AmqpConnection
  include Singleton

  attr_reader :connection, :channel

  def initialize
    begin
      @connection = Bunny.new(
        vhost: 'vhost',
        user: 'rabbitmq',
        password: 'password'
      )
      @connection.start
      @channel = @connection.create_channel
    rescue => error
      Rails.logger.error "🔴 AmqpConnection failed to initialize with error: #{error}"
    end
  end
end
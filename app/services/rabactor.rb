require 'bunny'

class Rabactor
  include Singleton

  def initialize
    @connection = Bunny.new(
      vhost: 'vhost',
      user: 'rabbitmq',
      password: 'password'
    )
    @connection.start
    @channel = @connection.create_channel()
    # @exchange = @channel.default_exchange
    Rails.logger.info '🟢 Rabactor initialized'
  end

=begin
  def publish(message)
    @exchange.publish(message, routing_key: 'test')
  end

  def close
    @connection.close
  end
=end
end
require 'bunny'

class RMQActor
  def initialize
    puts "RMQActor initialized"
    puts "🟢🟢🟢🟢🟢🟢🟢🟢🟢"
    @connection = Bunny.new
    @connection.start
    @channel = @connection.create_channel
    # @exchange = @channel.default_exchange
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
class AmqpExchange
  include Singleton

  attr_reader :hares_headers_exchange, :hares_direct_exchange, :hares_topic_exchange, :hares_fanout_exchange

  def initialize
    @hares_headers_exchange = AMQPConnection.channel.headers('hares.headers', durable: true)
    @hares_direct_exchange = AMQPConnection.channel.direct('hares.direct', durable: true)
    @hares_topic_exchange = AMQPConnection.channel.topic('hares.topic', durable: true)
    @hares_fanout_exchange = AMQPConnection.channel.fanout('hares.fanout', durable: true)

    set_up_dead_letter_x_and_q
  end

  def set_up_dead_letter_x_and_q
    @dead_letter_exchange = AMQPConnection.channel.fanout(DEAD_LETTER_EXCHANGE, durable: true)
    dead_letter_queue = AMQPConnection.channel.queue(DEAD_LETTER_QUEUE, durable: true)
    dead_letter_queue.bind(@dead_letter_exchange)
  end

  def default_queue_arguments
    { 'x-dead-letter-exchange': @dead_letter_exchange.name, 'x-message-ttl': 10000 }
  end
end


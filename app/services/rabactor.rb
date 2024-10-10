require 'bunny'

class Rabactor
  attr_reader :connection, :channel, :exchange
  include Singleton
  DEAD_LETTER_EXCHANGE = 'hares.dead-letter'
  DEAD_LETTER_QUEUE = 'hares.dead-letter-queue'

  def initialize
    begin
      @connection = Bunny.new(
        vhost: 'vhost',
        user: 'rabbitmq',
        password: 'password'
      )
      @connection.start
      @channel = @connection.create_channel()
      @hares_headers_exchange = @channel.headers('hares.headers', durable: true)

      set_up_dead_letter_x_and_q
      set_up_queues_and_bind_for_customers
      Rails.logger.info '🟢 Rabactor initialized'
    rescue => error
      Rails.logger.error "🔴 Rabactor failed to initialize with error: #{error}"
    end
  end

  def set_up_queue_for_headers(customer)
    queue = @channel.queue(
                            customer.headers_queue_name,
                            durable: true,
                            arguments: default_queue_arguments
                          )
    set_up_consumer(queue, customer) unless customer.id == 4
    set_up_binding(queue, customer)
  end

  def set_up_binding(queue, customer)
    queue.bind(@hares_headers_exchange,
               arguments: {
                 'x-match': 'all',
                 'membership': customer.membership,
                 'country': customer.country,
               })
  end

  private
  def default_queue_arguments
    {
      'x-dead-letter-exchange': @dead_letter_exchange.name,
      'x-message-ttl': 10000
    }
  end
  def set_up_dead_letter_x_and_q
    @dead_letter_exchange = @channel.fanout(DEAD_LETTER_EXCHANGE, durable: true)
    @dead_letter_queue = @channel.queue(DEAD_LETTER_QUEUE, durable: true)
    @dead_letter_queue.bind(@dead_letter_exchange)
  end
  def set_up_queues_and_bind_for_customers
    customers = Customer.all
    customers.each do |customer|
      set_up_queue_for_headers(customer)
    end
  end

  def set_up_consumer(queue, customer)
    queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      Rails.logger.info "🟢 Received #{payload} for #{customer.name}"
      @channel.ack(delivery_info.delivery_tag)
    end
  end
end
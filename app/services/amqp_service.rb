require 'bunny'

class AmqpService
  include Singleton
  attr_reader :connection, :channel, :exchange

  DEAD_LETTER_EXCHANGE = 'hares.dead-letter'
  DEAD_LETTER_QUEUE = 'hares.dead-letter-queue'

  ORDER_CREATED_ROUTING_KEY = 'order.created'
  ORDER_SHIPPED_ROUTING_KEY = 'order.shipped'
  ORDER_DELIVERED_ROUTING_KEY = 'order.delivered'

  INVENTORY_SERVICE = 'inventory-service'
  DELIVERY_SERVICE = 'delivery-service'
  CUSTOMER_SERVICE = 'customer-service'
  PEOPLE_SERVICE = 'people-service'

  # topic exchange format: logs.<resource-type>(order,customer).<process-type>(created,updated,deleted)

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
      @hares_direct_exchange = @channel.direct('hares.direct', durable: true)

      set_up_dead_letter_x_and_q
      set_up_queues_and_bind_for_customers
      set_up_order_status_queues

      Rails.logger.info '🟢 Rabactor initialized'
    rescue => error
      Rails.logger.error "🔴 Rabactor failed to initialize with error: #{error}"
    end
  end

  def headers_queue_name(customer)
    "customer-#{customer.id}-#{customer.name}"
  end

  def set_up_binding(queue, customer)
    queue.bind(@hares_headers_exchange,
               arguments: {
                 'x-match': 'all',
                 'membership': customer.membership,
                 'country': customer.country,
               })
  end

  def publish_order_created_event(order)
    @hares_direct_exchange.publish(order.to_json, routing_key: ORDER_CREATED_ROUTING_KEY)
  end

  def publish_order_shipped_event(order)
    @hares_direct_exchange.publish(order.to_json, routing_key: ORDER_SHIPPED_ROUTING_KEY)
  end

  def publish_order_delivered_event(order)
    @hares_direct_exchange.publish(order.to_json, routing_key: ORDER_DELIVERED_ROUTING_KEY)
  end

  def set_up_queue_for_headers(customer)
    queue = @channel.queue(
      headers_queue_name(customer),
      durable: true,
      arguments: default_queue_arguments
    )
    set_up_consumer(queue, customer) unless customer.id == 4
    set_up_binding(queue, customer)
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
      MicroservicesDigest
        .digest_message(
          PEOPLE_SERVICE,
          payload,
          "#{customer.country}-#{customer.membership}",
          headers_queue_name(customer)
        )
      @channel.ack(delivery_info.delivery_tag)
    end
  end

  def set_up_order_status_queues
    inventory_service_queue = @channel.queue(INVENTORY_SERVICE, durable: true, arguments: default_queue_arguments)
    inventory_service_queue.bind(@hares_direct_exchange, routing_key: ORDER_CREATED_ROUTING_KEY)

    delivery_service_queue = @channel.queue(DELIVERY_SERVICE, durable: true, arguments: default_queue_arguments)
    delivery_service_queue.bind(@hares_direct_exchange, routing_key: ORDER_SHIPPED_ROUTING_KEY)

    customer_service_queue = @channel.queue(CUSTOMER_SERVICE, durable: true, arguments: default_queue_arguments)
    customer_service_queue.bind(@hares_direct_exchange, routing_key: ORDER_DELIVERED_ROUTING_KEY)

    inventory_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(INVENTORY_SERVICE, payload, 'Order Created', INVENTORY_SERVICE)
      @channel.ack(delivery_info.delivery_tag)
    end

    delivery_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(DELIVERY_SERVICE, payload, 'Order Shipped', DELIVERY_SERVICE)
      @channel.ack(delivery_info.delivery_tag)
    end

    customer_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Order Delivered', CUSTOMER_SERVICE)
      @channel.ack(delivery_info.delivery_tag)
    end
  end
end
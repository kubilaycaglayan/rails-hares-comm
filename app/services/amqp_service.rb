require 'bunny'
require 'byebug'
class AmqpService
  include Singleton
  attr_reader :connection, :channel, :exchange, :hares_topic_exchange

  DEAD_LETTER_EXCHANGE = 'hares.dead-letter'
  DEAD_LETTER_QUEUE = 'hares.dead-letter-queue'

  INVENTORY_SERVICE = 'inventory-service'
  DELIVERY_SERVICE = 'delivery-service'
  CUSTOMER_SERVICE = 'customer-service'
  PEOPLE_SERVICE = 'people-service'
  ORDER_SERVICE = 'order-service'
  LOGS_SERVICE = 'logs-service'
  NOTIFICATION_SERVICE = 'notification-service'

  ORDER_CREATED = 'order.created'
  ORDER_SHIPPED = 'order.shipped'
  ORDER_DELIVERED = 'order.delivered'
  LOGS_ORDER_CREATED = 'logs.order.created'
  LOGS_ORDER_UPDATED = 'logs.order.updated'
  LOGS_ORDER_DELETED = 'logs.order.deleted'
  LOGS_CUSTOMER_CREATED = 'logs.customer.created'
  LOGS_CUSTOMER_UPDATED = 'logs.customer.updated'
  LOGS_CUSTOMER_DELETED = 'logs.customer.deleted'
  LOGS_SERVICE_ROUTING_KEY = 'logs.*.*'

  ORDER_SERVICE_CREATED_QUEUE = 'order-service.created'
  ORDER_SERVICE_UPDATED_QUEUE = 'order-service.updated'
  ORDER_SERVICE_DELETED_QUEUE = 'order-service.deleted'
  CUSTOMER_SERVICE_CREATED_QUEUE = 'customer-service.created'
  CUSTOMER_SERVICE_UPDATED_QUEUE = 'customer-service.updated'
  CUSTOMER_SERVICE_DELETED_QUEUE = 'customer-service.deleted'
  LOGS_SERVICE_QUEUE = 'logs-service-q'

  # topic exchange format: logs.<resource-type>(order,customer).<process-type>(created,updated,deleted)

  def initialize
    # print out the environment
    Rails.logger.info "ℹ️ Environment: #{Rails.env}"
    return if Rails.const_defined?('Console')

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
      @hares_topic_exchange = @channel.topic('hares.topic', durable: true)
      @hares_fanout_exchange = @channel.fanout('hares.fanout', durable: true)

      set_up_dead_letter_x_and_q
      set_up_queues_and_bind_for_customers
      set_up_order_status_queues
      set_up_topic_queues

      Rails.logger.info '🟢 AmqpService initialized'
    rescue => error
      Rails.logger.error "🔴 AmqpService failed to initialize with error: #{error}"
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
    @hares_direct_exchange.publish(order.to_json, routing_key: ORDER_CREATED)
    @hares_topic_exchange.publish(order.to_json, routing_key: LOGS_ORDER_CREATED)
  end

  def publish_order_shipped_event(order)
    @hares_direct_exchange.publish(order.to_json, routing_key: ORDER_SHIPPED)
    @hares_topic_exchange.publish(order.to_json, routing_key: LOGS_ORDER_UPDATED)
  end

  def publish_order_delivered_event(order)
    @hares_direct_exchange.publish(order.to_json, routing_key: ORDER_DELIVERED)
    @hares_topic_exchange.publish(order.to_json, routing_key: LOGS_ORDER_UPDATED)
  end

  def publish_customer_created_event(customer)
    @hares_topic_exchange.publish(customer.to_json, routing_key: LOGS_CUSTOMER_CREATED)
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

  def set_up_queue_for_fanout(customer)
    queue = @channel.queue(
      "user-message-#{customer.id}-#{customer.name}",
      durable: true,
      arguments: default_queue_arguments
    )
    queue.bind(@hares_fanout_exchange)
    set_up_consumer_for_messages_fanout(queue, customer)
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
      set_up_queue_for_fanout(customer)
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

  def set_up_consumer_for_messages_fanout(queue, customer)
    queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest
        .digest_message(
          NOTIFICATION_SERVICE,
          payload,
          "#{customer.country}-#{customer.membership}",
          "user-message-#{customer.id}-#{customer.name}"
        )
      @channel.ack(delivery_info.delivery_tag)
    end
  end

  def set_up_order_status_queues
    inventory_service_queue = @channel.queue(INVENTORY_SERVICE, durable: true, arguments: default_queue_arguments)
    inventory_service_queue.bind(@hares_direct_exchange, routing_key: ORDER_CREATED)

    delivery_service_queue = @channel.queue(DELIVERY_SERVICE, durable: true, arguments: default_queue_arguments)
    delivery_service_queue.bind(@hares_direct_exchange, routing_key: ORDER_SHIPPED)

    customer_service_queue = @channel.queue(CUSTOMER_SERVICE, durable: true, arguments: default_queue_arguments)
    customer_service_queue.bind(@hares_direct_exchange, routing_key: ORDER_DELIVERED)

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

  def set_up_topic_queues
    logs_order_created_queue = @channel.queue(ORDER_SERVICE_CREATED_QUEUE, durable: true, arguments: default_queue_arguments)
    logs_order_created_queue.bind(@hares_topic_exchange, routing_key: LOGS_ORDER_CREATED)

    logs_order_updated_queue = @channel.queue(ORDER_SERVICE_UPDATED_QUEUE, durable: true, arguments: default_queue_arguments)
    logs_order_updated_queue.bind(@hares_topic_exchange, routing_key: LOGS_ORDER_UPDATED)

    logs_order_deleted_queue = @channel.queue(ORDER_SERVICE_DELETED_QUEUE, durable: true, arguments: default_queue_arguments)
    logs_order_deleted_queue.bind(@hares_topic_exchange, routing_key: LOGS_ORDER_DELETED)

    logs_customer_created_queue = @channel.queue(CUSTOMER_SERVICE_CREATED_QUEUE, durable: true, arguments: default_queue_arguments)
    logs_customer_created_queue.bind(@hares_topic_exchange, routing_key: LOGS_CUSTOMER_CREATED)

    logs_customer_updated_queue = @channel.queue(CUSTOMER_SERVICE_UPDATED_QUEUE, durable: true, arguments: default_queue_arguments)
    logs_customer_updated_queue.bind(@hares_topic_exchange, routing_key: LOGS_CUSTOMER_UPDATED)

    logs_customer_deleted_queue = @channel.queue(CUSTOMER_SERVICE_DELETED_QUEUE, durable: true, arguments: default_queue_arguments)
    logs_customer_deleted_queue.bind(@hares_topic_exchange, routing_key: LOGS_CUSTOMER_DELETED)

    logs_service_queue = @channel.queue(LOGS_SERVICE_QUEUE, durable: true, arguments: default_queue_arguments)
    logs_service_queue.bind(@hares_topic_exchange, routing_key: LOGS_SERVICE_ROUTING_KEY)

    logs_order_created_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(ORDER_SERVICE, payload, 'Order Created', ORDER_SERVICE_CREATED_QUEUE)
      @channel.ack(delivery_info.delivery_tag)
    end

    logs_order_updated_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(ORDER_SERVICE, payload, 'Order Updated', ORDER_SERVICE_UPDATED_QUEUE)
      @channel.ack(delivery_info.delivery_tag)
    end

    logs_order_deleted_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(ORDER_SERVICE, payload, 'Order Deleted', ORDER_SERVICE_DELETED_QUEUE)
      @channel.ack(delivery_info.delivery_tag)
    end

    logs_customer_created_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Customer Created', CUSTOMER_SERVICE_CREATED_QUEUE)
      @channel.ack(delivery_info.delivery_tag)
    end

    logs_customer_updated_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Customer Updated', CUSTOMER_SERVICE_UPDATED_QUEUE)
      @channel.ack(delivery_info.delivery_tag)
    end

    logs_customer_deleted_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Customer Deleted', CUSTOMER_SERVICE_DELETED_QUEUE)
      @channel.ack(delivery_info.delivery_tag)
    end

    logs_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|

      MicroservicesDigest.digest_message(LOGS_SERVICE, payload, "#{delivery_info.routing_key}", LOGS_SERVICE_QUEUE)
      @channel.ack(delivery_info.delivery_tag)
    end
  end
end
require 'bunny'

class MicroserviceEmulator
  include Singleton
  def initialize
    set_up_queues_and_bind_for_customers
    set_up_order_status_queues
    set_up_topic_queues
  end

  def headers_queue_name(customer)
    "customer-#{customer.id}-#{customer.name}"
  end

  def set_up_binding(queue, customer)
    queue.bind(AMQPExchange.hares_headers_exchange,
               arguments: {
                 'x-match': 'all',
                 'membership': customer.membership,
                 'country': customer.country,
               })
  end

  def publish_order_created_event(order)
    AMQPExchange.hares_direct_exchange.publish(order.to_json, routing_key: ORDER_CREATED)
    AMQPExchange.hares_topic_exchange.publish(order.to_json, routing_key: LOGS_ORDER_CREATED)
  end

  def publish_order_shipped_event(order)
    AMQPExchange.hares_direct_exchange.publish(order.to_json, routing_key: ORDER_SHIPPED)
    AMQPExchange.hares_topic_exchange.publish(order.to_json, routing_key: LOGS_ORDER_UPDATED)
  end

  def publish_order_delivered_event(order)
    AMQPExchange.hares_direct_exchange.publish(order.to_json, routing_key: ORDER_DELIVERED)
    AMQPExchange.hares_topic_exchange.publish(order.to_json, routing_key: LOGS_ORDER_UPDATED)
  end

  def publish_customer_created_event(customer)
    AMQPExchange.hares_topic_exchange.publish(customer.to_json, routing_key: LOGS_CUSTOMER_CREATED)
  end

  def set_up_queue_for_headers(customer)
    queue = AMQPConnection.channel.queue(
      headers_queue_name(customer),
      durable: true,
      arguments: AMQPExchange.default_queue_arguments
    )
    set_up_consumer(queue, customer) unless customer.id == 4
    set_up_binding(queue, customer)
  end

  def set_up_queue_for_fanout(customer)
    queue = AMQPConnection.channel.queue(
      "user-message-#{customer.id}-#{customer.name}",
      durable: true,
      arguments: AMQPExchange.default_queue_arguments
    )
    queue.bind(AMQPExchange.hares_fanout_exchange)
    set_up_consumer_for_messages_fanout(queue, customer)
  end

private

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
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
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
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end
  end

  def set_up_order_status_queues
    inventory_service_queue = AMQPConnection.channel.queue(INVENTORY_SERVICE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    inventory_service_queue.bind(AMQPExchange.hares_direct_exchange, routing_key: ORDER_CREATED)

    delivery_service_queue = AMQPConnection.channel.queue(DELIVERY_SERVICE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    delivery_service_queue.bind(AMQPExchange.hares_direct_exchange, routing_key: ORDER_SHIPPED)

    customer_service_queue = AMQPConnection.channel.queue(CUSTOMER_SERVICE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    customer_service_queue.bind(AMQPExchange.hares_direct_exchange, routing_key: ORDER_DELIVERED)

    inventory_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(INVENTORY_SERVICE, payload, 'Order Created', INVENTORY_SERVICE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    delivery_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(DELIVERY_SERVICE, payload, 'Order Shipped', DELIVERY_SERVICE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    customer_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Order Delivered', CUSTOMER_SERVICE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end
  end

  def set_up_topic_queues
    logs_order_created_queue = AMQPConnection.channel.queue(ORDER_SERVICE_CREATED_QUEUE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    logs_order_created_queue.bind(AMQPExchange.hares_topic_exchange, routing_key: LOGS_ORDER_CREATED)

    logs_order_updated_queue = AMQPConnection.channel.queue(ORDER_SERVICE_UPDATED_QUEUE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    logs_order_updated_queue.bind(AMQPExchange.hares_topic_exchange, routing_key: LOGS_ORDER_UPDATED)

    logs_order_deleted_queue = AMQPConnection.channel.queue(ORDER_SERVICE_DELETED_QUEUE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    logs_order_deleted_queue.bind(AMQPExchange.hares_topic_exchange, routing_key: LOGS_ORDER_DELETED)

    logs_customer_created_queue = AMQPConnection.channel.queue(CUSTOMER_SERVICE_CREATED_QUEUE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    logs_customer_created_queue.bind(AMQPExchange.hares_topic_exchange, routing_key: LOGS_CUSTOMER_CREATED)

    logs_customer_updated_queue = AMQPConnection.channel.queue(CUSTOMER_SERVICE_UPDATED_QUEUE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    logs_customer_updated_queue.bind(AMQPExchange.hares_topic_exchange, routing_key: LOGS_CUSTOMER_UPDATED)

    logs_customer_deleted_queue = AMQPConnection.channel.queue(CUSTOMER_SERVICE_DELETED_QUEUE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    logs_customer_deleted_queue.bind(AMQPExchange.hares_topic_exchange, routing_key: LOGS_CUSTOMER_DELETED)

    logs_service_queue = AMQPConnection.channel.queue(LOGS_SERVICE_QUEUE, durable: true, arguments: AMQPExchange.default_queue_arguments)
    logs_service_queue.bind(AMQPExchange.hares_topic_exchange, routing_key: LOGS_SERVICE_ROUTING_KEY)

    logs_order_created_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(ORDER_SERVICE, payload, 'Order Created', ORDER_SERVICE_CREATED_QUEUE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    logs_order_updated_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(ORDER_SERVICE, payload, 'Order Updated', ORDER_SERVICE_UPDATED_QUEUE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    logs_order_deleted_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(ORDER_SERVICE, payload, 'Order Deleted', ORDER_SERVICE_DELETED_QUEUE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    logs_customer_created_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Customer Created', CUSTOMER_SERVICE_CREATED_QUEUE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    logs_customer_updated_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Customer Updated', CUSTOMER_SERVICE_UPDATED_QUEUE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    logs_customer_deleted_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
      MicroservicesDigest.digest_message(CUSTOMER_SERVICE, payload, 'Customer Deleted', CUSTOMER_SERVICE_DELETED_QUEUE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end

    logs_service_queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|

      MicroservicesDigest.digest_message(LOGS_SERVICE, payload, "#{delivery_info.routing_key}", LOGS_SERVICE_QUEUE)
      AMQPConnection.channel.ack(delivery_info.delivery_tag)
    end
  end
end
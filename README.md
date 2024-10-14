# README

- 'x-dead-letter-exchange', 'x-message-ttl' are defined on the queues NOT on bindings or exchanges or channels.
- 'x-match'(along with the optional headers) for headers exchange is defined on the bindings NOT on the exchanges or queues or channels.

- https://www.rabbitmq.com/docs/
- http://rubybunny.info/
- http://reference.rubybunny.info/

### Scenario:
You’re developing an e-commerce system, and you want to implement a notification system for different events like order updates, shipping, and promotions. You also want to ensure that any messages that can't be processed are routed to a dead-letter queue for further investigation.

### Problem:
You need to design a messaging system for this e-commerce platform using RabbitMQ, leveraging different exchange types and queues. Here’s how we can cover each concept:

1. Headers Exchange (for promotions)
   You have a promotion system where discounts are sent out based on customer attributes (e.g., country, membership level).

Create a headers exchange where messages contain headers like country=Turkey, membership=Gold.
Messages should route to queues based on these header values, so only users who match the criteria receive the promotion.
Question: How would you set up your headers exchange and binding to ensure only Turkish Gold members get a specific promotion?

2. Direct Exchange (for order status updates)
   Whenever an order status changes (e.g., OrderCreated, OrderShipped, OrderDelivered), you need to notify specific services (e.g., inventory, accounting, shipping).

Use a direct exchange to route these messages to specific queues depending on the exact routing key (e.g., OrderCreated -> inventory-service queue, OrderShipped -> shipping-service queue).
Task: Set up a direct exchange and define the appropriate bindings so each service only receives the order updates it needs.

3. Topic Exchange (for shipment notifications)
   You want to notify different services about shipments, but some services need more detailed information.

Use a topic exchange with routing keys like shipment.US.north or shipment.EU.south. This allows you to route based on patterns, such as sending all US-related shipments to one queue and Europe-related ones to another.
With topics, the routing key structure allows for flexible matching.
Challenge: Set up a topic exchange where shipment.# goes to a general queue, and shipment.US.* only routes to a queue for US shipments.

4. Fan-out Exchange (for promotional broadcasts)
   You want to send out a promotional message to all your users without filtering.

Use a fan-out exchange to broadcast the same message to all bound queues, ensuring everyone gets notified regardless of specific conditions.
Task: Implement a fan-out exchange that pushes promotional messages to multiple queues (e.g., mobile notification service, email service, SMS service).

5. Dead Letter Exchange (for failed processing)
   Some of your queues may not be able to process certain messages (e.g., a system is down).

Set up a dead-letter exchange for messages that can't be processed within a queue, ensuring these messages are routed to a separate dead-letter queue for debugging.
Challenge: Implement a dead-letter exchange for your order-status queue, and configure the TTL (time-to-live) for messages that can’t be processed within 30 seconds.

Bonus Question: How would you ensure that any messages in the dead-letter queue can be reprocessed or logged for later investigation?
class Order < ApplicationRecord
  after_create :publish_status_created
  after_update :publish_status_delivery
  belongs_to :customer

  def publish_status_created
    AMQPService.publish_order_created_event(self)
  end

  def publish_status_delivery
    if status == 'shipped'
      AMQPService.publish_order_shipped_event(self)
    elsif status == 'delivered'
      AMQPService.publish_order_delivered_event(self)
    end
  end
end

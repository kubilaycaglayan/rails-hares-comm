class Customer < ApplicationRecord
  after_create :create_queue
  def headers_queue_name
    "customer-#{id}-#{name}"
  end

  def create_queue
    AMQPService.set_up_queue_for_headers(self)
  end
end

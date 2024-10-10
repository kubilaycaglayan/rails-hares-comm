class Customer < ApplicationRecord
  after_create :create_queue

  def create_queue
    AMQPService.set_up_queue_for_headers(self)
  end
end

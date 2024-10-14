class Customer < ApplicationRecord
  after_create :create_queue
  attribute :name, :string

  validates :name, presence: true

  def create_queue
    AMQPService.set_up_queue_for_headers(self)
    AMQPService.publish_customer_created_event(self)
  end
end

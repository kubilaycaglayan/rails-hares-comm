class Customer < ApplicationRecord
  after_create :create_queue
  attribute :name, :string

  validates :name, presence: true

  def create_queue
    MSEmulator.set_up_queue_for_headers(self)
    MSEmulator.set_up_queue_for_fanout(self)
    MSEmulator.publish_customer_created_event(self)
  end
end

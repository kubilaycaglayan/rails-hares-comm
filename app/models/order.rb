class Order < ApplicationRecord
  belongs_to :customer

  validates :status, inclusion: { in: %w[created shipped delivered] }

  after_create :publish_status_created
  after_update :publish_status_delivery

  def publish_status_created
    MSEmulator.publish_order_created_event(self)
  end

  def publish_status_delivery
    if status == 'shipped'
      MSEmulator.publish_order_shipped_event(self)
    elsif status == 'delivered'
      MSEmulator.publish_order_delivered_event(self)
    end
  end
end

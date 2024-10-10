class MicroservicesDigest < ApplicationRecord
  def self.digest_message(name, message, note, queue)
    create(
      name:,
      message:,
      note:,
      queue:
    )
  end
end

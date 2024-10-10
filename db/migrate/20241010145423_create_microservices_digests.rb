class CreateMicroservicesDigests < ActiveRecord::Migration[7.1]
  def change
    create_table :microservices_digests do |t|
      t.string :name
      t.string :message
      t.string :note
      t.string :queue

      t.timestamps
    end
  end
end

class CreateCustomers < ActiveRecord::Migration[7.1]
  def change
    create_table :customers do |t|
      t.string :name
      t.string :country
      t.string :membership

      t.timestamps
    end
  end
end

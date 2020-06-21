class CreateEmployees < ActiveRecord::Migration[6.0]
  def change
    create_table :employees do |t|
      t.string :ssn, null: false
      t.index :ssn, unique: true
    end
  end
end

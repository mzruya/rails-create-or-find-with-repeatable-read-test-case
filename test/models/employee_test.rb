require 'test_helper'

# This test attempts to illustrate isolation level issues when using create_or_find_by!.
# It does so by driving two concurrent database connection.
# The Employee and EmployeeThroughADifferentConnection model both access the `employees` table.
class EmployeeTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  class EmployeeThroughADifferentConnection < ApplicationRecord
    establish_connection(:test)
    self.table_name = 'employees'
  end

  def transaction(isolation_level, ssn)
    Enumerator.new do |enum|
      employee = nil
      Employee.transaction(isolation: isolation_level) do
        enum.yield(:transaction_started)
        Employee.first
        enum.yield(:select_performed)
        employee = Employee.create_or_find_by!(ssn: ssn)
        enum.yield(:employee_created_or_found)
      end
      enum.yield(:transaction_ended)
      enum.yield(employee)
    end
  end

  def teardown
    Employee.delete_all
  end

  test 'Employee#ssn is unique' do
    Employee.create!(ssn: '1')
    assert_raise(ActiveRecord::RecordNotUnique) { Employee.create!(ssn: '1') }
  end

  test 'Employee and EmployeeThroughADifferentConnection are reading/writing to the same table' do
    Employee.create!(ssn: '1')
    EmployeeThroughADifferentConnection.create!(ssn: '2')
    assert_equal(Employee.all.map(&:ssn).sort, ['1', '2'])
    assert_equal(EmployeeThroughADifferentConnection.all.map(&:ssn).sort, ['1', '2'])
  end

  test 'Employee and EmployeeThroughADifferentConnection are using different database connections' do
    Employee.transaction(isolation: :repeatable_read) do
      EmployeeThroughADifferentConnection.transaction(isolation: :read_committed) {}
    end
  end

  test 'drives a transaction and creates an employee correctly' do
    transaction = transaction(:repeatable_read, '1')
    assert_equal(transaction.next, :transaction_started)
    assert_equal(transaction.next, :select_performed)
    assert_equal(transaction.next, :employee_created_or_found)
    assert_equal(transaction.next, :transaction_ended)
    assert_equal(transaction.next.ssn, '1')
  end

  test 'when the select happens before the record is created' do
    transaction = transaction(:repeatable_read, '1')
    assert_equal(transaction.next, :transaction_started)
    assert_equal(transaction.next, :select_performed)
    EmployeeThroughADifferentConnection.create!(ssn: '1')
    assert_raise(ActiveRecord::RecordNotFound) { transaction.next }
  end

  test 'when the select happens before the record is created, but the isolation level is read committed' do
    transaction = transaction(:read_committed, '1')
    assert_equal(transaction.next, :transaction_started)
    EmployeeThroughADifferentConnection.create!(ssn: '1')
    assert_equal(transaction.next, :select_performed)
    assert_equal(transaction.next, :employee_created_or_found)
    assert_equal(transaction.next, :transaction_ended)
    assert_equal(transaction.next.ssn, '1')
  end

  test 'when the select happens after the record is created' do
    transaction = transaction(:repeatable_read, '1')
    assert_equal(transaction.next, :transaction_started)
    EmployeeThroughADifferentConnection.create!(ssn: '1')
    assert_equal(transaction.next, :select_performed)
    assert_equal(transaction.next, :employee_created_or_found)
    assert_equal(transaction.next, :transaction_ended)
    assert_equal(transaction.next.ssn, '1')
  end
end

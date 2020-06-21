`ActiveRecord::Base.create_or_find_by/!` attempts improve on `ActiveRecord::Base.create_or_find_by/!` by avoiding race conditions that the previous implementation was susceptible to.

`create_or_find_by` attempts to first create the record while relying on the database uniqueness constraint to inform us if it already exists.
When the record does exist, it catches an exception and finds the record using the attributes provided. 

My initial expectaton from this method was that it's expected to return a record if used properly. even in concurrent situations.

The new strategy is still susceptible to race conditions, which are not mentioned in the docs, the behavior in these cases is dependent on the database isolation level. More concretely, `create_or_find_by` could raise a `RecordNotFound` if called from within an existing transaction in a repeatable reads isolation level.

Given how common it is for application code to already be running within an existing transaction (For example, code inside callbacks), and the fact that repeatable reads is the default isolation level for mysql, I think this is a fairly common use case. ,

the [`ActiveRecord::Base.create_or_find_by/!` docs](https://apidock.com/rails/v6.0.0/ActiveRecord/Relation/create_or_find_by) already mentions a few drawbacks to this approach, which I'll gladly submit a PR to improve on.

### A more thorough explanation

Repeatable read guarantees a consistent snapshot of the database, in innodb, the snapshot is established during the [first read](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html). This means that if our transaction performed a read before a record is created by another transaction, we won't "see" it. In respect to unqiueness constraints, if we try inserting a record that violates it, the database will still protect us, but if we try querying for the record, it'll seem like it doesn't exist.

I created a few [test cases](https://github.com/mzruya/rails-create-or-find-with-repeatable-read-test-case/blob/master/test/models/employee_test.rb#L60) that demonstrate this issue. 


[`ActiveRecord::Base.create_or_find_by/!`](https://apidock.com/rails/v6.0.0/ActiveRecord/Relation/create_or_find_by) attempts to improve on [`ActiveRecord::Base.find_or_create_by/!`](https://apidock.com/rails/v6.0.0/ActiveRecord/Relation/find_or_create_by) by avoiding race conditions that the previous implementation was susceptible to.

`create_or_find_by` attempts to first create the record while relying on the database uniqueness constraint to inform us if it already exists.
When the record does exist, it catches an exception and finds the record using the attributes provided. 

My initial expectation from the method was that if used properly, it's expected to return a record, even in concurrent situations.

The new strategy is still susceptible to race conditions, which are not mentioned in the docs, the behavior in these cases is dependent on the database isolation level. More concretely, `create_or_find_by` could raise a `RecordNotFound` if called from within an existing transaction in a repeatable reads isolation level.

Given how common it is for application code to already be running within an existing transaction (For example, code inside AR callbacks), and the fact that repeatable reads is the default isolation level for mysql, I think this is a fairly common use case.

### Reproduction

Repeatable read guarantees a consistent snapshot of the database, in innodb, the snapshot is established during the [first read](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html). This means that if our transaction performed a read before a record is created by another transaction, we won't "see" it. In respect to unqiueness constraints, if we try inserting a record that violates it, the database will still protect us, but if we try querying for the record, it'll seem like it doesn't exist.

I created a few [test cases](https://gist.github.com/mzruya/603f722ede1615fd7957cfd95a4d466c#file-test_create_or_find_by_race_condition-rb-L106) that demonstrate this issue.

### Suggestion

I do not think it's possible to actually "fix" this behavior, since it's inherent to how database isolation levels work.
I do think that there's a misconception (at least I had it) that `ActiveRecord::Base.create_or_find_by` is meant to be atomic and work correctly in concurrent situations. Therefore I think it'll make sense to document this as another drawback in the existing [docs](https://apidock.com/rails/v6.0.0/ActiveRecord/Relation/create_or_find_by). I'll gladly take a stab at improving the current docs if this seems reasonable.


Thank you!

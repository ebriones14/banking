# Banking

A plain Ruby component for account creation, deposits, withdrawals, transfers,
and balance lookup. Accounts and successful idempotency records are stored in
memory. No Rails application, HTTP API, or database is required.

## Setup

Use Ruby 3.4.6, as specified in `.tool-versions` and `.ruby-version`:

```bash
bundle install
bundle exec rspec
```

If your shell uses the macOS system Ruby, run through mise:

```bash
mise exec -- bundle install
mise exec -- bundle exec rspec
```

`bundle exec rake` also runs the complete suite. For an interactive console:

```bash
bundle exec irb -Ilib -rbanking
```

## Usage

```ruby
require "banking" # Add lib/ to the load path when running outside the project.

bank = Banking::Service.new
alice = bank.create_account(initial_deposit_in_cents: 10_000)
bob = bank.create_account(initial_deposit_in_cents: 5_000)

alice = bank.deposit(account_id: alice.id, amount_in_cents: 2_000)
bank.withdraw(account_id: alice.id, amount_in_cents: 1_000)
transfer = bank.transfer(
  from_account_id: alice.id,
  to_account_id: bob.id,
  amount_in_cents: 3_000
)
alice = transfer.from_account
bob = transfer.to_account

bank.balance(account_id: alice.id)  # => 8_000
bank.balance(account_id: bob.id)    # => 8_000
bank.accounts                       # => Array of current immutable accounts
```

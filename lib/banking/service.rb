require "securerandom"

module Banking
  class Service
    def initialize
      @accounts = {}
    end

    def create_account(initial_deposit_in_cents:)
      account = Account.new(
        id: SecureRandom.uuid,
        initial_balance_in_cents: initial_deposit_in_cents
      )

      @accounts[account.id] = account
      account
    end

    def accounts
      @accounts.values.dup
    end

    def deposit(account_id:, amount_in_cents:)
      account = @accounts.fetch(account_id)
      account.deposit(amount_in_cents: amount_in_cents)
    end
  end
end

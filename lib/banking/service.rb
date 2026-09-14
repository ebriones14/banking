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
      account = find_account(account_id)

      account.deposit(amount_in_cents: amount_in_cents)
    end

    def withdraw(account_id:, amount_in_cents:)
      account = find_account(account_id)

      account.withdraw(amount_in_cents: amount_in_cents)
    end

    def transfer(from_account_id:, to_account_id:, amount_in_cents:)
      if from_account_id == to_account_id
        raise InvalidTransferError, "source and destination accounts must be different"
      end

      from_account = find_account(from_account_id)
      to_account = find_account(to_account_id)

      from_account.withdraw(amount_in_cents: amount_in_cents)
      to_account.deposit(amount_in_cents: amount_in_cents)
    end

    private

    def find_account(account_id)
      @accounts.fetch(account_id) do
        raise InvalidAccountError, "account not found"
      end
    end
  end
end

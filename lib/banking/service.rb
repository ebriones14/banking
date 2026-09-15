require "securerandom"
require "thread"

module Banking
  class Service
    def initialize
      @accounts = {}
      @idempotency_records = {}
      @mutex = Mutex.new
    end

    def create_account(initial_deposit_in_cents:, idempotency_key: nil)
      execute_once(
        idempotency_key: idempotency_key,
        operation: :create_account,
        arguments: { initial_deposit_in_cents: initial_deposit_in_cents }
      ) do
        account = Account.new(
          id: SecureRandom.uuid,
          initial_balance_in_cents: initial_deposit_in_cents
        )

        @accounts[account.id] = account
        account
      end
    end

    def accounts
      @mutex.synchronize { @accounts.values.dup }
    end

    def balance(account_id:)
      @mutex.synchronize { find_account(account_id).balance_in_cents }
    end

    def deposit(account_id:, amount_in_cents:, idempotency_key: nil)
      execute_once(
        idempotency_key: idempotency_key,
        operation: :deposit,
        arguments: { account_id: account_id, amount_in_cents: amount_in_cents }
      ) do
        account = find_account(account_id)

        account.deposit(amount_in_cents: amount_in_cents)
      end
    end

    def withdraw(account_id:, amount_in_cents:, idempotency_key: nil)
      execute_once(
        idempotency_key: idempotency_key,
        operation: :withdraw,
        arguments: { account_id: account_id, amount_in_cents: amount_in_cents }
      ) do
        account = find_account(account_id)

        account.withdraw(amount_in_cents: amount_in_cents)
      end
    end

    def transfer(from_account_id:, to_account_id:, amount_in_cents:, idempotency_key: nil)
      execute_once(
        idempotency_key: idempotency_key,
        operation: :transfer,
        arguments: {
          from_account_id: from_account_id,
          to_account_id: to_account_id,
          amount_in_cents: amount_in_cents
        }
      ) do
        if from_account_id == to_account_id
          raise InvalidTransferError, "source and destination accounts must be different"
        end

        from_account = find_account(from_account_id)
        to_account = find_account(to_account_id)

        from_account.withdraw(amount_in_cents: amount_in_cents)
        to_account.deposit(amount_in_cents: amount_in_cents)
      end
    end

    private

    def find_account(account_id)
      @accounts.fetch(account_id) do
        raise InvalidAccountError, "account not found"
      end
    end

    def execute_once(idempotency_key:, operation:, arguments:)
      @mutex.synchronize do
        signature = [operation, arguments]
        record = @idempotency_records[idempotency_key] if idempotency_key

        if record
          unless record[:signature] == signature
            raise IdempotencyConflictError,
                  "idempotency key has already been used with different arguments"
          end

          return record[:result]
        end

        result = yield
        if idempotency_key
          @idempotency_records[idempotency_key] = {
            signature: signature,
            result: result
          }
        end
        result
      end
    end
  end
end

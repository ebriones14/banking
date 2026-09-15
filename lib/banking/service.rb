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
          id: generate_account_id,
          initial_balance_in_cents: initial_deposit_in_cents
        )

        @accounts[account.id] = account
        account
      end
    end

    def accounts
      @mutex.synchronize { @accounts.values }
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

        updated_account = account.deposit(amount_in_cents: amount_in_cents)
        @accounts = @accounts.merge(account.id => updated_account)
        updated_account
      end
    end

    def withdraw(account_id:, amount_in_cents:, idempotency_key: nil)
      execute_once(
        idempotency_key: idempotency_key,
        operation: :withdraw,
        arguments: { account_id: account_id, amount_in_cents: amount_in_cents }
      ) do
        account = find_account(account_id)

        updated_account = account.withdraw(amount_in_cents: amount_in_cents)
        @accounts = @accounts.merge(account.id => updated_account)
        updated_account
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

        updated_from_account = from_account.withdraw(amount_in_cents: amount_in_cents)
        updated_to_account = to_account.deposit(amount_in_cents: amount_in_cents)

        @accounts = @accounts.merge(
          from_account.id => updated_from_account,
          to_account.id => updated_to_account
        )
        TransferResult.new(
          from_account: updated_from_account,
          to_account: updated_to_account
        )
      end
    end

    private

    def generate_account_id
      loop do
        id = SecureRandom.uuid
        return id unless @accounts.key?(id)
      end
    end

    def find_account(account_id)
      @accounts.fetch(account_id) do
        raise InvalidAccountError, "account not found"
      end
    end

    def execute_once(idempotency_key:, operation:, arguments:)
      key = normalize_idempotency_key(idempotency_key)
      copied_arguments = arguments.transform_values do |value|
        value.is_a?(String) ? value.dup.freeze : value
      end.freeze
      signature = [operation, copied_arguments].freeze

      @mutex.synchronize do
        record = @idempotency_records[key] if key

        if record
          unless record[:signature] == signature
            raise IdempotencyConflictError,
                  "idempotency key has already been used with different arguments"
          end

          return record[:result]
        end

        result = yield
        if key
          @idempotency_records[key] = {
            signature: signature,
            result: result
          }
        end
        result
      end
    end

    def normalize_idempotency_key(key)
      return nil if key.nil?

      unless key.is_a?(String) && !key.strip.empty?
        raise InvalidIdempotencyKeyError, "idempotency key must be a non-empty string"
      end

      key.dup.freeze
    end
  end
end

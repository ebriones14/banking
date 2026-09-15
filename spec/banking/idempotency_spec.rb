RSpec.describe "Banking::Service idempotency and transactions" do
  subject(:service) { Banking::Service.new }

  describe "idempotent operations" do
    it "returns the original result even after a later balance change" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      request = { account_id: account.id, amount_in_cents: 1_000, idempotency_key: "stable-result" }
      original_result = service.deposit(**request)
      service.deposit(account_id: account.id, amount_in_cents: 2_000)

      expect(service.deposit(**request)).to equal(original_result)
      expect(service.balance(account_id: account.id)).to eq(13_000)
    end

    it "rejects a key reused for another operation" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      request = { account_id: account.id, amount_in_cents: 1_000, idempotency_key: "operation-conflict" }
      service.deposit(**request)

      expect { service.withdraw(**request) }.to raise_error(Banking::IdempotencyConflictError)
      expect(service.balance(account_id: account.id)).to eq(11_000)
    end

    it "allows a failed request to be retried after funds become available" do
      account = service.create_account(initial_deposit_in_cents: 100)
      request = { account_id: account.id, amount_in_cents: 200, idempotency_key: "retry-failure" }

      expect { service.withdraw(**request) }.to raise_error(Banking::InsufficientFundsError)
      service.deposit(account_id: account.id, amount_in_cents: 100)

      expect(service.withdraw(**request).balance_in_cents).to eq(0)
      expect(service.balance(account_id: account.id)).to eq(0)
    end

    it "treats calls without keys as independent operations" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      2.times { service.deposit(account_id: account.id, amount_in_cents: 1_000) }

      expect(service.balance(account_id: account.id)).to eq(12_000)
    end

    it "copies caller-owned strings used for request signatures" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      caller_id = account.id.dup
      caller_key = "copied-key"
      service.deposit(account_id: caller_id, amount_in_cents: 1_000, idempotency_key: caller_key)
      caller_id.replace("changed-id")
      caller_key.replace("changed-key")

      expect do
        service.deposit(account_id: account.id, amount_in_cents: 1_000, idempotency_key: "copied-key")
      end.not_to change { service.balance(account_id: account.id) }
    end

    ["", "  ", 123, false].each do |key|
      it "rejects invalid idempotency key #{key.inspect} before changing state" do
        expect do
          service.create_account(initial_deposit_in_cents: 100, idempotency_key: key)
        end.to raise_error(Banking::InvalidIdempotencyKeyError)

        expect(service.accounts).to be_empty
      end
    end

    it "creates an account only once when a request is retried" do
      first_result = service.create_account(
        initial_deposit_in_cents: 10_000,
        idempotency_key: "create-account-1"
      )
      second_result = service.create_account(
        initial_deposit_in_cents: 10_000,
        idempotency_key: "create-account-1"
      )

      expect(second_result).to equal(first_result)
      expect(service.accounts).to contain_exactly(first_result)
    end

    it "applies a retried deposit only once" do
      account = service.create_account(initial_deposit_in_cents: 10_000)

      2.times do
        service.deposit(
          account_id: account.id,
          amount_in_cents: 5_000,
          idempotency_key: "deposit-1"
        )
      end

      expect(service.balance(account_id: account.id)).to eq(15_000)
    end

    it "applies a retried withdrawal only once" do
      account = service.create_account(initial_deposit_in_cents: 10_000)

      2.times do
        service.withdraw(
          account_id: account.id,
          amount_in_cents: 4_000,
          idempotency_key: "withdraw-1"
        )
      end

      expect(service.balance(account_id: account.id)).to eq(6_000)
    end

    it "applies a retried transfer only once" do
      sender = service.create_account(initial_deposit_in_cents: 10_000)
      recipient = service.create_account(initial_deposit_in_cents: 5_000)

      request = {
        from_account_id: sender.id,
        to_account_id: recipient.id,
        amount_in_cents: 3_000,
        idempotency_key: "transfer-1"
      }
      first_result = service.transfer(**request)
      second_result = service.transfer(**request)

      expect(second_result).to equal(first_result)
      expect(service.balance(account_id: sender.id)).to eq(7_000)
      expect(service.balance(account_id: recipient.id)).to eq(8_000)
    end

    it "rejects reuse of a key with different arguments" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      service.deposit(
        account_id: account.id,
        amount_in_cents: 1_000,
        idempotency_key: "deposit-conflict"
      )

      expect do
        service.deposit(
          account_id: account.id,
          amount_in_cents: 2_000,
          idempotency_key: "deposit-conflict"
        )
      end.to raise_error(Banking::IdempotencyConflictError)

      expect(service.balance(account_id: account.id)).to eq(11_000)
    end
  end

  describe "concurrent transactions" do
    it "processes concurrent retries with the same key only once" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      ready = Queue.new
      start = Queue.new

      threads = 10.times.map do
        Thread.new do
          ready << true
          start.pop
          service.deposit(
            account_id: account.id,
            amount_in_cents: 1_000,
            idempotency_key: "concurrent-deposit"
          )
        end
      end
      10.times { ready.pop }
      10.times { start << true }
      threads.each(&:value)

      expect(service.balance(account_id: account.id)).to eq(11_000)
    end

    it "does not allow concurrent withdrawals to overdraw an account" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      ready = Queue.new
      start = Queue.new

      threads = 2.times.map do
        Thread.new do
          ready << true
          start.pop
          service.withdraw(account_id: account.id, amount_in_cents: 7_000)
          :success
        rescue Banking::InsufficientFundsError => error
          error
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      results = threads.map(&:value)

      expect(results.count(:success)).to eq(1)
      expect(results.grep(Banking::InsufficientFundsError).size).to eq(1)
      expect(service.balance(account_id: account.id)).to eq(3_000)
    end
  end
end

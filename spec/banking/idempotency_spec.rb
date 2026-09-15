RSpec.describe "Banking::Service idempotency and transactions" do
  subject(:service) { Banking::Service.new }

  describe "idempotent operations" do
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

      2.times do
        service.transfer(
          from_account_id: sender.id,
          to_account_id: recipient.id,
          amount_in_cents: 3_000,
          idempotency_key: "transfer-1"
        )
      end

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

      threads = 10.times.map do
        Thread.new do
          service.deposit(
            account_id: account.id,
            amount_in_cents: 1_000,
            idempotency_key: "concurrent-deposit"
          )
        end
      end
      threads.each(&:value)

      expect(service.balance(account_id: account.id)).to eq(11_000)
    end

    it "does not allow concurrent withdrawals to overdraw an account" do
      account = service.create_account(initial_deposit_in_cents: 10_000)

      results = 2.times.map do
        Thread.new do
          service.withdraw(account_id: account.id, amount_in_cents: 7_000)
          :success
        rescue Banking::InsufficientFundsError => error
          error
        end
      end.map(&:value)

      expect(results.count(:success)).to eq(1)
      expect(results.grep(Banking::InsufficientFundsError).size).to eq(1)
      expect(service.balance(account_id: account.id)).to eq(3_000)
    end
  end
end

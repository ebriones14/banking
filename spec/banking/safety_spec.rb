RSpec.describe "Banking::Service boundaries" do
  subject(:service) { Banking::Service.new }

  describe "initial deposits" do
    it "allows an account to start at zero" do
      account = service.create_account(initial_deposit_in_cents: 0)

      expect(service.balance(account_id: account.id)).to eq(0)
    end

    [-1, 100.5, "100", nil].each do |amount|
      it "rejects initial deposit #{amount.inspect} without creating an account" do
        expect do
          service.create_account(initial_deposit_in_cents: amount)
        end.to raise_error(Banking::InvalidAmountError)

        expect(service.accounts).to be_empty
      end
    end

    it "does not overwrite an account when a generated ID collides" do
      allow(SecureRandom).to receive(:uuid).and_return("first-id", "first-id", "second-id")
      first = service.create_account(initial_deposit_in_cents: 100)
      second = service.create_account(initial_deposit_in_cents: 200)

      expect(first.id).not_to eq(second.id)
      expect(service.accounts).to contain_exactly(first, second)
    end
  end

  describe "immutable accounts" do
    it "does not allow a caller to mutate the ID or balance" do
      account = service.create_account(initial_deposit_in_cents: 10_000)

      expect { account.id.replace("changed") }.to raise_error(FrozenError)
      expect(account).not_to respond_to(:balance_in_cents=)
      expect(account).to be_frozen
    end

    it "keeps returned snapshots stable without exposing stored balance mutations" do
      account = service.create_account(initial_deposit_in_cents: 10_000)
      proposed_account = account.deposit(amount_in_cents: 500)

      expect(proposed_account.balance_in_cents).to eq(10_500)
      expect(service.balance(account_id: account.id)).to eq(10_000)

      service.deposit(account_id: account.id, amount_in_cents: 1_000)

      expect(account.balance_in_cents).to eq(10_000)
      expect(service.accounts.first.balance_in_cents).to eq(11_000)
    end
  end

  describe "account lookup" do
    it "rejects an unknown balance lookup" do
      expect { service.balance(account_id: "missing") }.to raise_error(Banking::InvalidAccountError)
    end

    [:deposit, :withdraw].each do |operation|
      it "rejects #{operation} on an unknown account" do
        expect do
          service.public_send(operation, account_id: "missing", amount_in_cents: 100)
        end.to raise_error(Banking::InvalidAccountError)
      end
    end
  end

  describe "withdrawals" do
    it "allows withdrawing the full balance" do
      account = service.create_account(initial_deposit_in_cents: 10_000)

      updated_account = service.withdraw(
        account_id: account.id,
        amount_in_cents: 10_000
      )

      expect(updated_account.balance_in_cents).to eq(0)
      expect(service.balance(account_id: account.id)).to eq(0)
    end

    [0, -1, 100.5, "100", nil].each do |amount|
      it "rejects withdrawal #{amount.inspect} without changing the balance" do
        account = service.create_account(initial_deposit_in_cents: 10_000)

        expect do
          service.withdraw(account_id: account.id, amount_in_cents: amount)
        end.to raise_error(Banking::InvalidAmountError)

        expect(service.balance(account_id: account.id)).to eq(10_000)
      end
    end
  end

  describe "transfer preparation" do
    it "leaves the sender unchanged when the destination does not exist" do
      sender = service.create_account(initial_deposit_in_cents: 10_000)

      expect do
        service.transfer(from_account_id: sender.id, to_account_id: "missing", amount_in_cents: 100)
      end.to raise_error(Banking::InvalidAccountError)

      expect(service.balance(account_id: sender.id)).to eq(10_000)
    end

    [0, -1, 100.5].each do |amount|
      it "rejects transfer #{amount.inspect} without changing either account" do
        sender = service.create_account(initial_deposit_in_cents: 10_000)
        recipient = service.create_account(initial_deposit_in_cents: 5_000)

        expect do
          service.transfer(from_account_id: sender.id, to_account_id: recipient.id, amount_in_cents: amount)
        end.to raise_error(Banking::InvalidAmountError)

        expect(service.balance(account_id: sender.id)).to eq(10_000)
        expect(service.balance(account_id: recipient.id)).to eq(5_000)
      end
    end

    it "commits neither balance if credit preparation unexpectedly fails" do
      failing_account_class = Class.new(Banking::Account) do
        def deposit(amount_in_cents:)
          raise "credit preparation failed"
        end
      end
      stub_const("Banking::Account", failing_account_class)
      sender = service.create_account(initial_deposit_in_cents: 10_000)
      recipient = service.create_account(initial_deposit_in_cents: 5_000)

      expect do
        service.transfer(from_account_id: sender.id, to_account_id: recipient.id, amount_in_cents: 100)
      end.to raise_error(RuntimeError, "credit preparation failed")

      expect(service.balance(account_id: sender.id)).to eq(10_000)
      expect(service.balance(account_id: recipient.id)).to eq(5_000)
    end
  end
end

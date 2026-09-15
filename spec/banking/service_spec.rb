RSpec.describe "Banking::Service" do
  subject(:service) { Banking::Service.new }

  let(:initial_balance_in_cents) { 10_000 }
  let(:account) do
    service.create_account(initial_deposit_in_cents: initial_balance_in_cents)
  end

  describe "#create_account" do
    it "creates an account with a unique ID and the initial balance" do
      first_account = service.create_account(initial_deposit_in_cents: 10_000)
      second_account = service.create_account(initial_deposit_in_cents: 5_000)

      expect(first_account.id).not_to be_nil
      expect(first_account.id).not_to eq(second_account.id)
      expect(first_account.balance_in_cents).to eq(10_000)
      expect(second_account.balance_in_cents).to eq(5_000)
    end
  end

  describe "#accounts" do
    it "returns all created accounts" do
      first_account = service.create_account(initial_deposit_in_cents: 10_000)
      second_account = service.create_account(initial_deposit_in_cents: 5_000)

      expect(service.accounts).to contain_exactly(first_account, second_account)
    end

    it "does not expose the internal account collection" do
      created_account = account

      service.accounts.clear

      expect(service.accounts).to contain_exactly(created_account)
    end
  end

  describe "#deposit" do
    it "increases the account balance by the deposited amount" do
      updated_account = nil

      expect do
        updated_account = service.deposit(
          account_id: account.id,
          amount_in_cents: 5_000
        )
      end.to change { service.balance(account_id: account.id) }.from(10_000).to(15_000)

      expect(updated_account.id).to eq(account.id)
      expect(updated_account.balance_in_cents).to eq(15_000)
      expect(updated_account).not_to equal(account)
    end

    it "rejects a zero deposit and leaves the balance unchanged" do
      expect do
        service.deposit(account_id: account.id, amount_in_cents: 0)
      end.to raise_error(
        Banking::InvalidAmountError,
        "amount must be greater than zero"
      )

      expect(service.balance(account_id: account.id)).to eq(10_000)
    end

    it "rejects a negative deposit and leaves the balance unchanged" do
      expect do
        service.deposit(account_id: account.id, amount_in_cents: -5_000)
      end.to raise_error(
        Banking::InvalidAmountError,
        "amount must be greater than zero"
      )

      expect(service.balance(account_id: account.id)).to eq(10_000)
    end

    it "rejects a non-integer deposit and leaves the balance unchanged" do
      expect do
        service.deposit(account_id: account.id, amount_in_cents: 100.50)
      end.to raise_error(
        Banking::InvalidAmountError,
        "amount must be an integer"
      )

      expect(service.balance(account_id: account.id)).to eq(10_000)
    end
  end

  describe "#withdraw" do
    it "decreases the account balance by the withdrawn amount" do
      updated_account = nil

      expect do
        updated_account = service.withdraw(
          account_id: account.id,
          amount_in_cents: 9_000
        )
      end.to change { service.balance(account_id: account.id) }.from(10_000).to(1_000)

      expect(updated_account.id).to eq(account.id)
      expect(updated_account.balance_in_cents).to eq(1_000)
      expect(updated_account).not_to equal(account)
    end

    it "rejects a withdrawal that exceeds the account balance" do
      expect do
        service.withdraw(
          account_id: account.id,
          amount_in_cents: 19_000
        )
      end.to raise_error(Banking::InsufficientFundsError)

      expect(service.balance(account_id: account.id)).to eq(10_000)
    end
  end

  describe "#transfer" do
    let(:sender) { account }
    let(:recipient) do
      service.create_account(initial_deposit_in_cents: 5_000)
    end

    it "moves money between accounts while preserving their combined balance" do
      combined_balance = sender.balance_in_cents + recipient.balance_in_cents

      result = service.transfer(
        from_account_id: sender.id,
        to_account_id: recipient.id,
        amount_in_cents: 3_000
      )

      expect(result.from_account.id).to eq(sender.id)
      expect(result.from_account.balance_in_cents).to eq(7_000)
      expect(result.to_account.id).to eq(recipient.id)
      expect(result.to_account.balance_in_cents).to eq(8_000)
      expect(result).to be_frozen
      expect(service.balance(account_id: sender.id)).to eq(7_000)
      expect(service.balance(account_id: recipient.id)).to eq(8_000)
      expect(
        service.balance(account_id: sender.id) + service.balance(account_id: recipient.id)
      ).to eq(combined_balance)
    end

    it "rejects an overdraft and leaves both account balances unchanged" do
      expect do
        service.transfer(
          from_account_id: sender.id,
          to_account_id: recipient.id,
          amount_in_cents: 11_000
        )
      end.to raise_error(Banking::InsufficientFundsError)

      expect(service.balance(account_id: sender.id)).to eq(10_000)
      expect(service.balance(account_id: recipient.id)).to eq(5_000)
    end

    it "rejects a transfer if an account is not found" do
      expect do
        service.transfer(
          from_account_id: nil,
          to_account_id: recipient.id,
          amount_in_cents: 1_000
        )
      end.to raise_error(Banking::InvalidAccountError)

      expect(service.balance(account_id: recipient.id)).to eq(5_000)
    end

    it "rejects transfers where the sender and recipient IDs are the same" do
      expect do
        service.transfer(
          from_account_id: sender.id,
          to_account_id: sender.id,
          amount_in_cents: 4_000
        )
      end.to raise_error(Banking::InvalidTransferError)

      expect(service.balance(account_id: sender.id)).to eq(10_000)
    end
  end

  describe "#balance" do
    it "returns the account balance in cents" do
      expect(service.balance(account_id: account.id)).to eq(10_000)
    end

    it "returns the updated balance after a deposit" do
      service.deposit(account_id: account.id, amount_in_cents: 5_000)

      expect(service.balance(account_id: account.id)).to eq(15_000)
    end
  end
end

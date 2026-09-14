module Banking
  class Account
    attr_reader :id, :balance_in_cents

    def initialize(id:, initial_balance_in_cents:)
      @id = id
      @balance_in_cents = initial_balance_in_cents
    end

    def deposit(amount_in_cents:)
      validate_amount!(amount_in_cents)

      @balance_in_cents += amount_in_cents
    end

    def withdraw(amount_in_cents:)
      validate_amount!(amount_in_cents)
      validate_sufficient_funds!(amount_in_cents)

      @balance_in_cents -= amount_in_cents
    end

    private

    def validate_amount!(amount_in_cents)
      raise InvalidAmountError, "amount must be an integer" unless amount_in_cents.is_a?(Integer)
      raise InvalidAmountError, "amount must be greater than zero" unless amount_in_cents.positive?
    end

    def validate_sufficient_funds!(amount_in_cents)
      raise InsufficientFundsError, "amount must not be greater than current balance" if @balance_in_cents < amount_in_cents
    end
  end
end

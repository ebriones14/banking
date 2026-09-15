module Banking
  class Account
    attr_reader :id, :balance_in_cents

    def initialize(id:, initial_balance_in_cents:)
      raise InvalidAmountError, "initial balance must be an integer" unless initial_balance_in_cents.is_a?(Integer)
      raise InvalidAmountError, "initial balance must not be negative" if initial_balance_in_cents.negative?

      @id = id.dup.freeze
      @balance_in_cents = initial_balance_in_cents
      freeze
    end

    def deposit(amount_in_cents:)
      validate_amount!(amount_in_cents)

      with_balance(@balance_in_cents + amount_in_cents)
    end

    def withdraw(amount_in_cents:)
      validate_amount!(amount_in_cents)
      validate_sufficient_funds!(amount_in_cents)

      with_balance(@balance_in_cents - amount_in_cents)
    end

    private

    def with_balance(balance_in_cents)
      self.class.new(id: id, initial_balance_in_cents: balance_in_cents)
    end

    def validate_amount!(amount_in_cents)
      raise InvalidAmountError, "amount must be an integer" unless amount_in_cents.is_a?(Integer)
      raise InvalidAmountError, "amount must be greater than zero" unless amount_in_cents.positive?
    end

    def validate_sufficient_funds!(amount_in_cents)
      if @balance_in_cents < amount_in_cents
        raise InsufficientFundsError, "insufficient funds"
      end
    end
  end
end

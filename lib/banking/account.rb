module Banking
  class Account
    attr_reader :id, :balance_in_cents

    def initialize(id:, initial_balance_in_cents:)
      @id = id
      @balance_in_cents = initial_balance_in_cents
    end
  end
end

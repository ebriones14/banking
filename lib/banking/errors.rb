module Banking
  class InvalidAmountError < StandardError; end
  class InsufficientFundsError < StandardError; end
  class InvalidAccountError < StandardError; end
  class InvalidTransferError < StandardError; end
  class IdempotencyConflictError < StandardError; end
  class InvalidIdempotencyKeyError < StandardError; end
end

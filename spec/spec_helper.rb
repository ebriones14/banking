require_relative "../lib/banking"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
  config.order = :random
  Kernel.srand config.seed
end

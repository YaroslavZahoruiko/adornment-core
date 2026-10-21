# frozen_string_literal: true

require "adornment/core"
require_relative "support/types"
require_relative "support/helpers"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
  config.include SpecHelpers

  # Every example must leave no pending declaration in its fiber.
  config.after do |example|
    idle = SpecHelpers.idle?
    SpecHelpers.force_idle!
    raise "pending declarations left after the example" unless idle || example.exception || example.metadata[:leaves_pending]
  end
end

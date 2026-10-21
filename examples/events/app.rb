# frozen_string_literal: true

# An application using the events extension (examples/events/events.rb):
#
#   ruby -I lib examples/events/app.rb
require_relative "events"

# Handlers, as an application writes them.
class Billing
  include Events::Handler

  On "order.paid"
  def send_receipt(order) = "receipt for order #{order}"

  On "order.paid"
  On "order.refunded"
  def record(order) = "ledger entry for order #{order}"
end

if $PROGRAM_NAME == __FILE__
  Adornment.verify_all!(lint: :error)
  routes = Events.compile
  puts Events.publish(routes, "order.paid", 42)
  puts Events.publish(routes, "order.refunded", 7)
end

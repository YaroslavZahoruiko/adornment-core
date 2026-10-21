# frozen_string_literal: true

# A small extension built only on adornment-core's public API: methods subscribe to events with
# an annotation, the extension discovers them once and compiles plain callables, and publishing
# an event never calls Adornment. examples/events/app.rb uses it.
require "adornment/core"

# The extension: its annotation type, its opt-in module and its compiler.
module Events
  # `On "order.paid"` above a method that handles the event's payload.
  class On
    include Adornment::Annotation[repeatable: true, targets: [:instance]]

    attr_reader :event

    def initialize(event)
      @event = event.to_s
    end

    # Checked when the annotation attaches: a handler takes the payload as its only argument.
    def validate(site)
      return if site.method.arity == 1

      raise ArgumentError, "an event handler takes the payload as its only argument"
    end
  end

  # Opt-in for handler classes: `include Events::Handler` enables `On(...)` above methods.
  module Handler
    def self.included(base)
      super
      base.include(Adornment[On])
    end
  end

  # Discovers every handler method once and returns `{event => [callables]}`, frozen.
  def self.compile
    routes = {}
    Adornment.annotated_with(On).each do |klass, methods|
      handler = klass.new
      methods.each do |name, subscriptions|
        subscriptions.each { |on| (routes[on.event] ||= []) << handler.method(name) }
      end
    end
    routes.transform_values(&:freeze).freeze
  end

  # Calls every handler of `event` with `payload`: plain method calls, no Adornment.
  def self.publish(routes, event, payload)
    routes.fetch(event, []).map { |handler| handler.call(payload) }
  end
end

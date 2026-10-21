# frozen_string_literal: true

module Adornment
  module Core
    # Checks on annotation types, shared by the facade, the owner API and reflection.
    # @api private
    module Utils
      # @api private
      # @param type [Class] an annotation type
      # @return [Symbol] the declaration method name of a type without an alias: the last segment of
      #   its constant name
      # @raise [ArgumentError] for a non-annotation type, or an anonymous one
      def self.declaration_name(type)
        check_type!(type)
        name = type.name or raise ArgumentError, "anonymous annotation type #{type.inspect} needs an alias (Name: type)"
        name.split("::").last.to_sym
      end

      # Raises unless `type` is a method annotation type: a class that included
      # `Adornment::Annotation[...]` (the policy module is the only way in).
      # @api private
      # @param type [Object]
      # @return [void]
      # @raise [ArgumentError]
      def self.check_type!(type)
        return if type.is_a?(Class) && type < Annotation

        raise ArgumentError, "#{type.inspect} is not an annotation type; include Adornment::Annotation[...]"
      end

      # @api private
      # @param args [Array] positional arguments
      # @param options [Hash] keyword arguments
      # @return [String] call arguments as written: `Integer, default: 1`
      def self.render_arguments(args, options)
        [*args.map(&:inspect), *options.map { |key, value| "#{key}: #{value.inspect}" }].join(", ")
      end
    end
  end
end

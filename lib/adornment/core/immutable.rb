# frozen_string_literal: true

module Adornment
  module Core
    # Deep-frozen copies of annotation values (public as {Adornment.immutable_copy}).
    #
    # Array, Hash, Set and String values are copied and frozen, recursively; the caller's objects
    # are never mutated or frozen. Other objects are kept by reference. A value that is already
    # deeply immutable (`Ractor.shareable?`, which CRuby answers in O(1) once an object is known
    # to be shareable) is returned as it is, since nobody can mutate it. The identity table that
    # preserves cycles and shared subgraphs is allocated only when a container is traversed.
    # @api private
    module Immutable
      extend self

      # @param value [Object]
      # @param seen [Hash{Object => Object}, nil] originals to their copies (identity), shared by a
      #   traversal so cycles and shared subgraphs are copied once
      # @return [Object] a deep-frozen copy of a String, Array, Hash or Set; `value` itself when it
      #   is already deeply immutable or of any other class
      def copy(value, seen = nil)
        case value
        when String
          value.frozen? ? value : value.dup.freeze
        when Array, Hash, Set
          return value if Ractor.shareable?(value)

          container(value, seen || {}.compare_by_identity)
        else
          value
        end
      end

      # Copies an Array, Hash or Set whose elements may need copying.
      # @param value [Array, Hash, Set]
      # @param seen [Hash{Object => Object}] see {copy}
      # @return [Array, Hash, Set] a frozen copy (a Hash keeps `compare_by_identity`)
      def container(value, seen)
        return seen[value] if seen.key?(value)

        case value
        when Array
          seen[value] = out = []
          value.each { |v| out << copy(v, seen) }
        when Hash
          seen[value] = out = value.compare_by_identity? ? {}.compare_by_identity : {}
          value.each { |k, v| out[copy(k, seen)] = copy(v, seen) }
        else # Set
          seen[value] = out = Set.new
          value.each { |v| out << copy(v, seen) }
        end
        out.freeze
      end
    end
  end
end

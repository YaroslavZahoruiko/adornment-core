# frozen_string_literal: true

module Adornment
  module Core
    # Lookups behind {Reflection}. The resolved method is found through Ruby's own lookup
    # (`instance_method(name).owner`): one UnboundMethod, no ancestors. The queries that read
    # overridden methods walk the ancestors, nearest first, through each module with its own entry
    # for the name, and stop at an undef barrier. A visibility change (`private :inherited`) is an
    # own entry like any other.
    # @api private
    module Query
      # The shared empty result.
      NONE = State::NONE

      extend self

      # Yields `(holder, side, annotations)` for each module the walk visits. The first yield is
      # the resolved method.
      # @param owner [Module]
      # @param name [Symbol]
      # @param singleton [Boolean]
      # @yieldparam holder [Module] the class or module that holds the entry
      # @yieldparam side [:instance, :singleton]
      # @yieldparam annotations [Array<Adornment::Annotation>] frozen, possibly empty
      # @return [nil]
      def each_entry(owner, name, singleton)
        start = singleton ? owner.singleton_class : owner
        return unless start.method_defined?(name) || start.private_method_defined?(name)

        ancestors = start.ancestors
        i = next_own(ancestors, 0, name)
        while i
          holder, side = holder_of(ancestors[i])
          yield holder, side, State.of(holder)&.entry(side, name) || NONE
          later = next_own(ancestors, i + 1, name)
          break if later.nil? || undef_between?(ancestors, i, later, name)

          i = later
        end
        nil
      end

      # The resolved method's annotations: those of the module Ruby's lookup names
      # (`instance_method(name).owner`).
      # @param owner [Module]
      # @param name [Symbol]
      # @param singleton [Boolean]
      # @return [Array<Adornment::Annotation>] frozen; empty when nothing is attached or the method
      #   is not defined
      def resolved_entry(owner, name, singleton)
        start = singleton ? owner.singleton_class : owner
        return NONE unless start.method_defined?(name) || start.private_method_defined?(name)

        mod = start.instance_method(name).owner
        entry = if mod.singleton_class?
                  State.of(mod.attached_object)&.entry(:singleton,
                                                       name)
                else
                  State.of(mod)&.entry(:instance, name)
                end
        entry || NONE
      end

      # Whether `mod` has its own entry for `name` (modules prepended to it do not count).
      # @param mod [Module]
      # @param name [Symbol]
      # @return [Boolean]
      def own?(mod, name)
        mod.method_defined?(name, false) || mod.private_method_defined?(name, false)
      end

      # @param ancestors [Array<Module>]
      # @param from [Integer]
      # @param name [Symbol]
      # @return [Integer, nil] the index of the first module at or after `from` with its own entry
      def next_own(ancestors, from, name)
        i = from
        while i < ancestors.size
          return i if own?(ancestors[i], name)

          i += 1
        end
        nil
      end

      # Whether a module strictly between the two indexes undefines `name` (an undef entry is not
      # an own entry, so it is never found by {next_own}).
      # @param ancestors [Array<Module>]
      # @param from [Integer]
      # @param to [Integer]
      # @param name [Symbol]
      # @return [Boolean]
      def undef_between?(ancestors, from, to, name)
        i = from + 1
        while i < to
          return true if ancestors[i].undefined_instance_methods.include?(name)

          i += 1
        end
        false
      end

      # @param mod [Module] an ancestor, possibly a singleton class
      # @return [Array(Module, Symbol)] the class or module holding `mod`'s entries, and the side
      def holder_of(mod)
        mod.singleton_class? ? [mod.attached_object, :singleton] : [mod, :instance]
      end

      # The resolved method's annotations, filtered by `type`.
      # @param owner [Module]
      # @param name [Symbol]
      # @param type [Class, nil]
      # @param singleton [Boolean]
      # @return [Array<Adornment::Annotation>] frozen
      def annotations_for(owner, name, type, singleton)
        annotations = resolved_entry(owner, name, singleton)
        return annotations if type.nil? || annotations.all?(type)

        annotations.select { |a| a.is_a?(type) }.freeze
      end

      # Names with an entry in some ancestor (activated ones), in ancestor order.
      # @param owner [Module]
      # @param singleton [Boolean]
      # @return [Array<Symbol>]
      def candidate_names(owner, singleton)
        names = []
        (singleton ? owner.singleton_class : owner).ancestors.each do |mod|
          entries = mod.singleton_class? ? State.of(mod.attached_object)&.entries(:singleton) : State.of(mod)&.entries(:instance)
          names.concat(entries.keys) if entries
        end
        names.uniq
      end
    end
  end
end

# frozen_string_literal: true

module Adornment
  module Core
    # An owner's annotation methods: one per annotation type, named after it (`Traced(...)`),
    # declaring an annotation of that type for the next definition. Extended into the owner, so
    # its subclasses inherit them and nothing is defined globally.
    # @api private
    class AnnotationMethods < Module
      # @return [Hash{Symbol => Class}] frozen; method name => annotation type
      attr_reader :types

      # @param owner [Module]
      # @return [AnnotationMethods] the owner's own module, created and extended into the owner on
      #   first use (a subclass of an activated class gets its own on its first `use_annotations`)
      def self.for(owner)
        state = State.for(owner)
        methods = state.annotation_methods || state.lock.synchronize { state.annotation_methods ||= new(owner) }
        owner.extend(methods) unless owner.singleton_class.include?(methods) # outside the lock
        methods
      end

      # @param owner [Module]
      # @return [Hash{Symbol => Class}] the annotation methods usable on `owner` (its own and
      #   inherited ones; nearer modules win)
      def self.types_of(owner)
        owner.singleton_class.ancestors.grep(AnnotationMethods).reverse_each.inject({}) { |all, d| all.merge(d.types) }
      end

      # @param owner [Module] the owner this module belongs to (shown by {#inspect})
      def initialize(owner)
        super()
        @owner = owner
        @types = {}.freeze
      end

      # Defines the method `name`, which declares `type.new(*args, **kwargs)` for the next
      # definition of the receiver. Adding the same name and type again does nothing; another type
      # under the same name replaces the method.
      # @param name [Symbol]
      # @param type [Class] an annotation type
      # @return [void]
      def add(name, type)
        return if @types[name].equal?(type) # activated again with the same vocabulary

        remove_method(name) if @types.key?(name)
        @types = @types.merge(name => type).freeze
        define_method(name) do |*args, **kwargs, &block|
          raise ArgumentError, "#{name}(...) takes no block" if block

          location = caller_locations(1, 1).first # the user's declaration, captured once
          Attachment.declare(self, type.new(*args, **kwargs), location)
        end
      end

      # @return [String] `#<Adornment::Core::AnnotationMethods Owner>`
      def inspect = "#<Adornment::Core::AnnotationMethods #{@owner.inspect}>"
      alias to_s inspect
    end
  end
end

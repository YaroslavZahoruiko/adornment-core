# frozen_string_literal: true

module Adornment
  module Core
    # The anonymous module returned by `Adornment[...]`. Including it activates the includer
    # (`extend Target`) and defines its declaration methods (`use_annotations`).
    class Base < Module
      # @api private
      # @param types [Array<Class>] annotation types
      # @param aliases [Hash{Symbol => Class}] declaration method name => annotation type
      # @raise [ArgumentError] for a class that is not an annotation type
      def initialize(types, aliases)
        super()
        types.each { |t| Core::Utils.check_type!(t) }
        aliases.each_value { |t| Core::Utils.check_type!(t) }
        @types = types.dup.freeze
        @aliases = aliases.transform_keys(&:to_sym).freeze
      end

      # @return [String] e.g. `Adornment[Traced, Cache: Cached]`
      def inspect
        parts = @types.map { |t| t.name || t.inspect } + @aliases.map { |k, t| "#{k}: #{t.name || t.inspect}" }
        "Adornment[#{parts.join(', ')}]"
      end
      alias to_s inspect

      private

      # Activates the includer and defines its declaration methods.
      def included(base)
        super
        base.extend(Target)
        base.use_annotations(*@types, **@aliases)
      end

      def extend_object(_base)
        raise ArgumentError, "extend #{inspect} is not supported; use include #{inspect}"
      end

      def prepend_features(_base)
        raise ArgumentError, "prepend #{inspect} is not supported; use include #{inspect}"
      end
    end

    # Owner API for declaring: `extend Adornment::Core::Target`, then `use_annotations`.
    # `include Adornment[...]` does both in one line. Extending activates the owner.
    module Target
      # Activation: the owner is registered for discovery, gets the read-only {Reflection} API,
      # the definition hooks (once per ancestry: a subclass of an activated class inherits them)
      # and, for a module, {Core::Propagation} to pass reflection on to its includers. The owner's
      # state is created on first use.
      # @api private
      # @param base [Module] the owner being activated
      # @raise [ArgumentError] for a singleton class or anything that is not a class or module
      def self.extended(base)
        super
        unless base.is_a?(Module) && !base.singleton_class?
          raise ArgumentError, "Adornment can only activate classes and modules, not #{base.inspect}"
        end

        Core::Registry.register(base) # also after an unregister
        singleton = base.singleton_class
        base.extend(Reflection) unless singleton.include?(Reflection)
        singleton.prepend(Core::Hooks) unless singleton.include?(Core::Hooks)
        singleton.prepend(Core::Propagation) unless base.is_a?(Class) || singleton.include?(Core::Propagation)
      end

      # Defines one declaration method per type, named after the last segment of the type's
      # constant name, or after the alias key: `use_annotations Traced, Cache: MyLib::Cached`.
      #
      # @param types [Array<Class>] method annotation types
      # @param aliases [Hash{Symbol => Class}] declaration method name => type
      # @return [nil]
      # @raise [ArgumentError] for anonymous types without an alias, non-annotation types, or a
      #   name that collides with a singleton method not defined by Adornment
      def use_annotations(*types, **aliases)
        named = types.to_h { |t| [Core::Utils.declaration_name(t), t] }.merge(aliases.transform_keys(&:to_sym))
        named.each_value { |type| Core::Utils.check_type!(type) }
        named.each_key do |name|
          next unless respond_to?(name, true) # Check for collisions with other methods
          next if method(name).owner.is_a?(AnnotationMethods) # Check if the method is defined by Adornment

          raise ArgumentError, "#{inspect}.#{name} already exists and was not defined by Adornment; " \
                               "rename the declaration method with an alias (#{name.to_s.downcase}_alias: Type)"
        end
        annotation_methods = Core::AnnotationMethods.for(self)
        named.each { |name, type| annotation_methods.add(name, type) }
        nil
      end

      # Declares annotation instances for the next method definition, without declaration methods:
      # `adorn Route.new("/users")`, `adorn ADMIN_ONLY`, `adorn first, second`. Only instances:
      # build them with `Type.new(...)`.
      #
      # @param annotations [Array<Adornment::Annotation>]
      # @return [nil]
      # @raise [ArgumentError] with no arguments, or for a type or any other non-instance
      # @raise [Adornment::DuplicateAnnotation] for a second non-repeatable annotation of one type
      # @raise [Adornment::LeftoverAnnotations] when another owner still has pending declarations
      def adorn(*annotations)
        raise ArgumentError, "adorn needs at least one annotation instance" if annotations.empty?

        location = caller_locations(1, 1).first
        annotations.each { |annotation| Core::Attachment.declare(self, annotation, location) }
        nil
      end

      # Raises if this owner has declarations (in the current fiber) that never attached, and
      # clears them.
      #
      # @return [nil]
      # @raise [Adornment::LeftoverAnnotations]
      def verify_adornments! = Core::Attachment.verify(self)
    end
  end
end

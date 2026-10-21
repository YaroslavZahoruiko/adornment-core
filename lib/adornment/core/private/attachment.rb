# frozen_string_literal: true

module Adornment
  module Core
    # Declaration, definitions and verification, plus the activation check and the reflection grant
    # for includers. Activation itself is {Target.extended}.
    # @api private
    module Attachment
      # --- activation and propagation ------------------------------------------------------

      extend self

      # @param owner [Object]
      # @return [Boolean] whether `owner` is a class or module with the definition hooks
      def activated?(owner) = owner.is_a?(Module) && owner.singleton_class.include?(Hooks)

      # Includers, prependers and extenders of activated modules get the read-only reflection API,
      # as activated owners do. Modules among the includers and prependers pass it on to their own
      # includers.
      # @param base [Module] the includer, prepender or extender
      # @param kind [:include, :prepend, :extend]
      # @return [void]
      def grant(base, kind)
        base.extend(Reflection) unless base.singleton_class.include?(Reflection)
        return if kind == :extend || base.is_a?(Class)

        base.singleton_class.prepend(Propagation) unless base.singleton_class.include?(Propagation)
      end

      # --- declaration -----------------------------------------------------------------------

      # The shared enqueue of every declaration path (declaration methods and `adorn`).
      #
      # @param owner [Module] the class or module declaring
      # @param annotation [Adornment::Annotation]
      # @param location [Thread::Backtrace::Location, nil] the user's call, captured once by the
      #   public entry point with `caller_locations(1, 1)` and formatted lazily
      # @return [nil]
      # @raise [ArgumentError] when `annotation` is not an annotation instance
      # @raise [Adornment::DuplicateAnnotation, Adornment::LeftoverAnnotations] see {Pending.push!}
      def declare(owner, annotation, location)
        check_instance!(annotation)
        Pending.push!(owner, annotation, location)
      end

      # Raises unless `annotation` is a method annotation instance.
      # @param annotation [Object]
      # @return [void]
      # @raise [ArgumentError] naming `Type.new(...)` when `annotation` is a type
      def check_instance!(annotation)
        return if annotation.is_a?(Annotation)

        if annotation.is_a?(Class) && annotation < Annotation
          raise ArgumentError, "#{annotation.inspect} is an annotation type, not an instance; " \
                               "pass #{annotation.short_name}.new(...)"
        end
        raise ArgumentError, "expected an Adornment annotation instance, got #{annotation.inspect}"
      end

      # --- definitions -----------------------------------------------------------------------

      # A new entry for `name` on `owner`, which has pending declarations: it takes them,
      # replacing the entry's annotations. Every entry Ruby reports counts: definitions, copies
      # (aliases, `module_function`) and visibility changes of inherited methods alike.
      # The pending declarations are taken first, so a failed check leaves none behind and
      # attaches nothing.
      # @param owner [Module]
      # @param name [Symbol]
      # @param side [:instance, :singleton]
      # @return [void]
      # @raise [Adornment::InvalidTarget] for an annotation whose type does not target `side`
      # @raise [Adornment::DefinitionError] when a validator rejects the method
      def added(owner, name, side)
        pending = Pending.take(owner)
        annotations = pending.map(&:annotation).freeze
        unless annotations.all? { |a| a.class.targets.include?(side) }
          wrong = annotations.reject { |a| a.class.targets.include?(side) }
          raise InvalidTarget, "#{describe(owner, name, side)}: #{wrong.map(&:inspect).join(', ')} " \
                               "cannot annotate #{side} methods (targets: #{wrong.first.class.targets.inspect})"
        end
        site = Site.new(owner, name, side, annotations)
        pending.each { |declaration| validate!(declaration, site) }
        State.for(owner).set_entry(side, name, annotations)
      end

      # Runs one declaration's validator; a StandardError becomes a DefinitionError (its cause)
      # pointing at the declaration.
      # @param declaration [Pending::PendingDeclaration]
      # @param site [Site]
      # @return [void]
      # @raise [Adornment::DefinitionError] with the validator's error as `cause`
      def validate!(declaration, site)
        declaration.annotation.validate(site)
      rescue StandardError => e
        location = declaration.location
        error = DefinitionError.new("#{site.label}: #{e.message}" \
                                    "#{" (declared at #{location})" if location}")
        error.set_backtrace(location ? [location, *caller] : caller)
        raise error, cause: e
      end

      # --- verification ----------------------------------------------------------------------

      # Takes the owner's pending declarations and raises if there were any.
      # @param owner [Module]
      # @return [nil]
      # @raise [Adornment::LeftoverAnnotations]
      def verify(owner)
        left = Pending.take(owner)
        raise LeftoverAnnotations.new({ owner => left }) unless left.empty?

        nil
      end

      # @param owner [Module]
      # @param name [Symbol]
      # @param side [:instance, :singleton]
      # @return [String] `Owner#name` or `Owner.name`
      def describe(owner, name, side) = "#{owner.inspect}#{side == :singleton ? '.' : '#'}#{name}"
    end
  end
end

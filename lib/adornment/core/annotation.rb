# frozen_string_literal: true

module Adornment
  # Method annotation types are ordinary named classes configured by including
  # `Adornment::Annotation[...]`. Their fields are instance variables set by an ordinary
  # `initialize`, so Ruby itself decides what is positional, what is a keyword and what is
  # required:
  #
  #   class Route
  #     include Adornment::Annotation[repeatable: true]
  #
  #     attr_reader :path, :verbs
  #
  #     def initialize(path, verbs: [:GET])
  #       @path = path
  #       @verbs = verbs.map(&:to_sym)
  #     end
  #   end
  #
  # After `initialize` returns, `new` copies and deep-freezes every instance variable
  # ({Adornment.immutable_copy}) and freezes the instance, so an initializer neither freezes nor
  # copies anything itself. Every instance variable is a field: it takes part in `==`, `hash`,
  # `to_h`, inspection and pattern matching.
  #
  # This module is the instance marker of method annotations. Including it bare is an error:
  # `Adornment::Annotation[...]` (or `[]` for the defaults) returns the policy module that
  # includes it. Policies: `repeatable:` (false) and `targets:` (`[:instance, :singleton]`).
  module Annotation
    class << self
      # @param args [Array] must be empty: policies are keywords
      # @param policies [Hash] `repeatable:`, `targets:`; only the given ones are stored (the
      #   others are inherited, or defaults)
      # @return [Adornment::Core::PolicyModule] the policy module to include
      # @raise [ArgumentError] for positional arguments, unknown policies or invalid values
      def [](*args, **policies)
        unless args.empty?
          raise ArgumentError, "Adornment::Annotation[...] takes policies as keywords " \
                               "(#{Core::Policies::KEYS.map { |k| "#{k}:" }.join(', ')}), got #{args.map(&:inspect).join(', ')}"
        end

        Core::PolicyModule.new(policies)
      end

      private

      def append_features(base)
        return super if base.is_a?(Core::PolicyModule)

        raise ArgumentError, "use include Adornment::Annotation[...] (policies, or [] for the defaults), " \
                             "not bare Adornment::Annotation"
      end

      def prepend_features(_base)
        raise ArgumentError, "use include Adornment::Annotation[...], not prepend"
      end

      def extend_object(_base)
        raise ArgumentError, "use include Adornment::Annotation[...], not extend"
      end
    end

    # Attachment-time check, called with the {Core::Site} the annotation is about to attach to
    # (once per annotation; every annotation of one definition gets the same site, with the
    # complete proposed set). Read and raise; never mutate. A `StandardError` raised here is
    # re-raised as {Adornment::DefinitionError} (its `cause`) and nothing is attached. Called
    # again for every attachment, so it must tolerate repeats. The default does nothing.
    #
    # @param site [Adornment::Core::Site]
    # @return [void]
    def validate(site); end

    # @yieldparam field [Symbol]
    # @yieldparam value [Object]
    # @yieldreturn [Array(Object, Object)] a key-value pair, as for `Hash#to_h` with a block
    # @return [Hash{Symbol => Object}] the fields (instance variables without `@`), in the order
    #   the initializer set them; with a block, the pairs it returns
    def to_h(&block)
      out = {}
      instance_variables.each { |ivar| out[ivar.name.delete_prefix("@").to_sym] = instance_variable_get(ivar) }
      block ? out.to_h(&block) : out
    end

    # Pattern matching on the fields: `in { path: String => path }`.
    # @param _keys [Array<Symbol>, nil] ignored: every field is returned
    # @return [Hash{Symbol => Object}]
    def deconstruct_keys(_keys) = to_h

    # Same class and equal fields (`==` on each instance variable).
    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      return true if equal?(other)
      return false unless other.class == self.class

      ivars = instance_variables
      return false unless ivars.size == other.instance_variables.size

      ivars.each do |ivar|
        unless other.instance_variable_defined?(ivar) && instance_variable_get(ivar) == other.instance_variable_get(ivar)
          return false
        end
      end
      true
    end

    # Same class and `eql?` fields: the Hash-key equality that matches {#hash}.
    # @param other [Object]
    # @return [Boolean]
    def eql?(other)
      return true if equal?(other)
      return false unless other.class == self.class

      ivars = instance_variables
      return false unless ivars.size == other.instance_variables.size

      ivars.each do |ivar|
        unless other.instance_variable_defined?(ivar) && instance_variable_get(ivar).eql?(other.instance_variable_get(ivar))
          return false
        end
      end
      true
    end

    # @return [Integer] from the class and the fields, independent of field order
    def hash = [self.class, to_h].hash

    # @return [String] `#<TypeName field=value, ...>`
    def inspect
      name = self.class.name || "Adornment::Annotation"
      pairs = instance_variables.map do |ivar|
        "#{ivar.name.delete_prefix('@')}=#{instance_variable_get(ivar).inspect}"
      end
      pairs.empty? ? "#<#{name}>" : "#<#{name} #{pairs.join(', ')}>"
    end
    alias to_s inspect
  end

  module Core
    # The module `Adornment::Annotation[...]` returns: the explicitly given policies, plus the
    # method annotation marker. Including it in a class makes that class a method annotation type.
    # @api private
    class PolicyModule < Module
      # @return [Hash] the explicitly given policies (frozen)
      attr_reader :overrides

      # @param policies [Hash] validated by {Policies.validate}
      # @raise [ArgumentError] for unknown policies or invalid values
      def initialize(policies)
        super()
        @overrides = Policies.validate(policies)
        include(Annotation) # passes Annotation's guard: this is a PolicyModule

        freeze
      end

      # @return [String] e.g. `Adornment::Annotation[repeatable: true]`
      def inspect = "Adornment::Annotation[#{@overrides.map { |k, v| "#{k}: #{v.inspect}" }.join(', ')}]"
      alias to_s inspect

      private

      # Checks the host, includes the module, then installs the type behavior on the host.
      def append_features(host)
        Policies.check_host!(self, host)
        super
        Policies.install(host)
        host
      end

      def prepend_features(_host)
        raise ArgumentError, "use include #{inspect}, not prepend"
      end

      def extend_object(_host)
        raise ArgumentError, "use include #{inspect}, not extend"
      end
    end

    # Merges and validates method annotation policies. Each policy module stores only its
    # overrides; a type's policy merges the policy modules of its ancestors, least specific first,
    # then applies the defaults. The merged policy is cached on the type and dropped (for the type
    # and its subclasses) whenever a policy module is included.
    # @api private
    module Policies
      # The policy names `Annotation[...]` accepts.
      KEYS = %i[repeatable targets].freeze
      # The method kinds a type may target.
      SIDES = %i[instance singleton].freeze
      # The policy of a type that sets nothing.
      DEFAULTS = { repeatable: false, targets: SIDES }.freeze
      # The instance variable caching a type's merged policy.
      IVAR = :@__adornment_policy__

      @lock = Mutex.new

      class << self
        # @param policies [Hash] `repeatable:` and/or `targets:`
        # @return [Hash] the validated, frozen overrides
        # @raise [ArgumentError] for unknown keys, a non-boolean `repeatable:`, or `targets:`
        #   that is not a non-empty subset of {SIDES}
        def validate(policies)
          unknown = policies.keys - KEYS
          unless unknown.empty?
            raise ArgumentError, "unknown annotation polic(y/ies) #{unknown.map { |k| "#{k}:" }.join(', ')}; " \
                                 "allowed: #{KEYS.map { |k| "#{k}:" }.join(', ')}"
          end

          out = {}
          policies.each { |key, value| out[key] = key == :repeatable ? boolean(value) : sides(value) }
          out.freeze
        end

        # @param type [Class] an annotation type
        # @return [Hash] the type's merged policy (frozen), computed once and cached on the type
        #   (a frozen type cannot hold the cache, so it is merged on every read)
        def of(type)
          cached = type.instance_variable_get(IVAR)
          return cached if cached

          policy = merged(type.ancestors.grep(PolicyModule))
          type.frozen? ? policy : type.instance_variable_set(IVAR, policy)
        end

        # Checks an inclusion into `host` before Ruby includes it: a plain class.
        # @param mod [PolicyModule] the module being included (for the message)
        # @param host [Module]
        # @return [void]
        # @raise [ArgumentError] for a module, a `Data` or a `Struct` subclass
        def check_host!(mod, host)
          return if host.is_a?(Class) && !(host < Data) && !(host < Struct)

          raise ArgumentError, "#{mod.inspect} can only be included in a plain class " \
                               "(fields are instance variables set by initialize), not #{host.inspect}"
        end

        # Installs the class behavior after the inclusion and drops cached policies below `host`.
        # @param host [Class] the new (or re-configured) annotation type
        # @return [void]
        def install(host)
          @lock.synchronize { forget(host) }
          host.extend(TypeMethods)
        end

        # Applies the freezing rule to an initialized instance: every instance variable is copied
        # and deep-frozen, then the instance is frozen. An instance its initializer froze already
        # is kept as it is.
        # @param instance [Adornment::Annotation]
        # @return [Adornment::Annotation] `instance`, frozen
        def seal(instance)
          return instance if instance.frozen?

          instance.instance_variables.each do |ivar|
            value = instance.instance_variable_get(ivar)
            copied = Immutable.copy(value)
            instance.instance_variable_set(ivar, copied) unless copied.equal?(value)
          end
          instance.freeze
        end

        private

        # Drops the cached policy of `type` and of its subclasses (recursively).
        def forget(type)
          type.remove_instance_variable(IVAR) if type.instance_variable_defined?(IVAR) && !type.frozen?
          type.subclasses.each { |sub| forget(sub) }
        end

        # Policy modules nearest first => the merged, defaulted policy.
        def merged(modules)
          out = {}
          modules.reverse_each { |m| out.merge!(m.overrides) }
          DEFAULTS.merge(out).freeze
        end

        # @return [Boolean] `value`, when it is true or false
        def boolean(value)
          return value if [true, false].include?(value)

          raise ArgumentError, "repeatable: must be true or false, got #{value.inspect}"
        end

        # @return [Array<Symbol>] the frozen, de-duplicated sides `value` names
        def sides(value)
          list = Array(value).map { |t| t.respond_to?(:to_sym) ? t.to_sym : t }.uniq
          if list.empty? || !(list - SIDES).empty?
            raise ArgumentError, "targets: must be a non-empty subset of #{SIDES.inspect}, got #{value.inspect}"
          end

          list.freeze
        end
      end
    end

    # Class-level construction and readers of annotation types.
    # @api private
    module TypeMethods
      # Ruby's own construction (the initializer's positional and keyword parameters), then the
      # freezing rule ({Policies.seal}).
      # @return [Adornment::Annotation] frozen
      def new(...) = Policies.seal(super)

      # @return [String] the last segment of the constant name (`Traced` for `Obs::Traced`)
      def short_name = name ? name.split("::").last : inspect

      # @return [Boolean] whether several annotations of this type may annotate one method
      def repeatable? = adornment_policy[:repeatable]

      # @return [Array<Symbol>] the method kinds (`:instance`, `:singleton`) the type may annotate
      def targets = adornment_policy[:targets]

      # @api private
      # @return [Hash] the merged policy
      def adornment_policy = @__adornment_policy__ || Policies.of(self)

      # Not a constructor for method annotations: they are declared above the method.
      # @param args [Array] shown in the error as the call form
      # @param kwargs [Hash] shown in the error as the call form
      # @return [void] never returns
      # @raise [TargetError] always, naming the call form (`Get["/x"]` → `Get("/x")`)
      def [](*args, **kwargs)
        raise TargetError, "#{short_name} is a method annotation; write it as a call above the method: " \
                           "`#{short_name}(#{Core::Utils.render_arguments(args, kwargs)})`"
      end
    end
  end
end

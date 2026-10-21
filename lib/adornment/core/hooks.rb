# frozen_string_literal: true

module Adornment
  module Core
    # Passes the reflection API on to includers, prependers and extenders of a module: prepended to
    # activated modules at activation, and by {Attachment.grant} to plain modules that include or
    # prepend one (Ruby calls `included` only on the module included directly, so each module in
    # the chain must pass it on). Classes never get it: nothing includes a class.
    # @api private
    module Propagation
      # Grants reflection to the includer, then calls the next `included`. The arguments are
      # forwarded unchanged, so an `included do ... end` DSL defined on the module (called with no
      # base and a block) keeps working.
      # @param args [Array] the includer, as Ruby passes it (or nothing, for a DSL block call)
      # @return [Object] whatever the next `included` returns
      def included(*args, &)
        Attachment.grant(args[0], :include) if args[0].is_a?(Module)
        super
      end

      # Grants reflection to the prepender, then calls the next `prepended`.
      # @param args [Array] the prepender, as Ruby passes it
      # @return [Object] whatever the next `prepended` returns
      def prepended(*args, &)
        Attachment.grant(args[0], :prepend) if args[0].is_a?(Module)
        super
      end

      # Grants reflection to the extender (the extended object's singleton side), then calls the
      # next `extended`.
      # @param args [Array] the extended object, as Ruby passes it
      # @return [Object] whatever the next `extended` returns
      def extended(*args, &)
        Attachment.grant(args[0], :extend) if args[0].is_a?(Module)
        super
      end

      private :included, :prepended, :extended
    end

    # Definition hooks prepended to an activated owner's singleton class (once per ancestry:
    # subclasses inherit them). A definition takes the owner's pending declarations; a definition
    # with nothing pending does nothing, so ordinary definitions cost one fiber-local lookup.
    # Like any Ruby hook, an owner's own `method_added` must call `super`.
    # @api private
    module Hooks
      # An instance method entry was added: it takes the owner's pending declarations, if any.
      # @param name [Symbol]
      # @return [Object] whatever the next `method_added` returns
      # @raise [Adornment::InvalidTarget, Adornment::DefinitionError] from the attachment checks
      def method_added(name)
        Attachment.added(self, name, :instance) if Pending.for?(self)
        super
      end

      # A singleton method entry was added: it takes the owner's pending declarations, if any.
      # @param name [Symbol]
      # @return [Object] whatever the next `singleton_method_added` returns
      # @raise [Adornment::InvalidTarget, Adornment::DefinitionError] from the attachment checks
      def singleton_method_added(name)
        Attachment.added(self, name, :singleton) if Pending.for?(self)
        super
      end

      # A constant was added to the owner: pending declarations can no longer attach.
      # @param name [Symbol]
      # @return [Object] whatever the next `const_added` returns
      # @raise [Adornment::LeftoverAnnotations] when the owner has pending declarations
      def const_added(name)
        Pending.const_added(self, name)
        super
      end

      private :method_added, :singleton_method_added, :const_added
    end
  end
end

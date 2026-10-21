# frozen_string_literal: true

module Adornment
  module Core
    # Per-owner state, held in a hidden instance variable of the owner (so it lives and dies with
    # the owner; nothing global refers to it strongly).
    #
    # Entries (attached annotations) are one Hash per side, written under the lock and read
    # without it. Readers of a single entry get a frozen Array: CRuby runs `Hash#[]` and
    # `Hash#[]=` with Symbol keys atomically under the GVL, so a reader sees the old or the new
    # value. A whole-side read freezes the Hash in place and returns it as the snapshot; the next
    # write copies it into a new mutable Hash first. So writing N names in a row costs O(N) (not
    # O(N^2) as with a copy per write), and at rest only one Hash per side exists.
    #
    # The lock guards the entry writes; no user code runs under it. Pending declarations are not
    # kept here (see {Pending}).
    # @api private
    class State
      # The owner's instance variable that holds its state.
      IVAR = :@__adornment_state__
      # Guards the creation of states (one per owner).
      CREATE_LOCK = Mutex.new
      # The shared empty entry.
      NONE = [].freeze

      # @param owner [Module]
      # @return [State, nil] the owner's state; nil when it has none yet
      def self.of(owner) = owner.instance_variable_get(IVAR)

      # @param owner [Module]
      # @return [State] the owner's state, created on first use. Creating it registers the owner:
      #   activation registers too, but a subclass of an activated class inherits the hooks without
      #   being activated, and is registered when it first declares.
      def self.for(owner)
        owner.instance_variable_get(IVAR) || CREATE_LOCK.synchronize do
          owner.instance_variable_get(IVAR) || begin
            state = new
            owner.instance_variable_set(IVAR, state)
            Registry.register(owner)
            state
          end
        end
      end

      # @return [Mutex] guards entry writes and the creation of {#annotation_methods}
      attr_reader :lock

      # @return [AnnotationMethods, nil] the owner's declaration methods module, once created
      attr_accessor :annotation_methods

      def initialize
        @lock = Mutex.new
        @instance = {}
        @singleton = {}
        @annotation_methods = nil
      end

      # @param side [:instance, :singleton]
      # @param name [Symbol]
      # @return [Array<Annotation>, nil] frozen; nil when the method never took declarations
      def entry(side, name)
        (side == :singleton ? @singleton : @instance)[name]
      end

      # @param side [:instance, :singleton]
      # @return [Hash{Symbol => Array<Annotation>}] frozen snapshot of a side
      def entries(side)
        live = side == :singleton ? @singleton : @instance
        return live if live.frozen?

        @lock.synchronize { (side == :singleton ? @singleton : @instance).freeze }
      end

      # Replaces the entry for `name`.
      # @param side [:instance, :singleton]
      # @param name [Symbol]
      # @param value [Array<Annotation>] frozen
      # @return [nil]
      def set_entry(side, name, value)
        @lock.synchronize { writable(side)[name] = value }
        nil
      end

      # The side's mutable Hash (a frozen snapshot is copied first). Called under the lock.
      # @param side [:instance, :singleton]
      # @return [Hash{Symbol => Array<Annotation>}]
      def writable(side)
        live = side == :singleton ? @singleton : @instance
        return live unless live.frozen?

        live = live.dup
        side == :singleton ? @singleton = live : @instance = live
      end
    end

    # Weak registry of activated owners, for global discovery and verification.
    # `ObjectSpace::WeakMap` is used because `ObjectSpace::WeakKeyMap` cannot enumerate its keys.
    # @api private
    module Registry
      @map = ObjectSpace::WeakMap.new
      @lock = Mutex.new

      class << self
        # @param owner [Module]
        # @return [void]
        def register(owner) = @lock.synchronize { @map[owner] = true }

        # @param owner [Module]
        # @return [void]
        def unregister(owner) = @lock.synchronize { @map.delete(owner) }

        # @return [Array<Module>] the reachable registered owners (a copy)
        def owners = @lock.synchronize { @map.keys }
      end
    end
  end
end

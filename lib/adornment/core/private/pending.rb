# frozen_string_literal: true

module Adornment
  module Core
    # Pending declarations: one fiber-local Hash, `{owner => [PendingDeclaration, ...]}`, that
    # compares owners by identity (no user `hash`/`eql?` is called).
    #
    # Declarations wait for the next method definition of the owner they were made on, so at
    # most one owner has pending declarations at a time. These raise {LeftoverAnnotations}
    # (and clear the pending declarations):
    #
    # - a declaration on another owner while declarations are still pending;
    # - a constant added to the owner while it has pending declarations (a nested
    #   `class Inner`, `X = ...`), via `const_added`.
    #
    # Nothing traces body ends: declarations left at the end of a body stay pending until one of
    # the above, the owner's next definition, or verification. Pending declarations are seen
    # only by their own fiber.
    # @api private
    module Pending
      # The fiber-local key of the table.
      KEY = :__adornment_core_pending__
      # The shared empty result.
      NONE = [].freeze

      # A declaration waiting for the next method definition.
      #
      # The caller location is kept as captured and formatted only when it is read (diagnostics).
      class PendingDeclaration
        # @return [Adornment::Annotation]
        attr_reader :annotation

        # @api private
        # @param annotation [Adornment::Annotation]
        # @param location [Thread::Backtrace::Location, nil] the declaration's caller location
        def initialize(annotation, location)
          @annotation = annotation
          @location = location
          freeze
        end

        # @return [String, nil] `path:line` of the declaration
        def location
          loc = @location
          loc && "#{loc.path}:#{loc.lineno}"
        end

        # @api private
        # @return [Thread::Backtrace::Location, nil] the location as captured
        def raw_location = @location

        # @return [String] `#<Adornment::Core::Pending::PendingDeclaration #<Traced> at path:line>`
        def inspect = "#<Adornment::Core::Pending::PendingDeclaration #{@annotation.inspect}#{" at #{location}" if @location}>"
        alias to_s inspect
      end

      extend self

      # @return [Hash{Module => Array<PendingDeclaration>}] this fiber's table (created on first
      #   use, compared by identity), at most one entry
      def table
        Thread.current[KEY] ||= {}.compare_by_identity
      end

      # @return [Boolean] whether this fiber has no pending declarations at all
      def empty? = table.empty?

      # @param owner [Module]
      # @return [Boolean] whether `owner` has pending declarations in this fiber
      def for?(owner)
        t = table
        !t.empty? && t.key?(owner)
      end

      # Queues `annotation`, declared at `location`, for `owner`.
      # @param owner [Module]
      # @param annotation [Adornment::Annotation]
      # @param location [Thread::Backtrace::Location, nil]
      # @return [nil]
      # @raise [LeftoverAnnotations] when another owner still has pending declarations
      # @raise [DuplicateAnnotation] for a second non-repeatable annotation of one type (the
      #   owner's pending declarations are cleared first)
      def push!(owner, annotation, location)
        t = table
        unless t.empty? || t.key?(owner)
          left = take_all
          raise LeftoverAnnotations.new(left, "#{owner.inspect} got a declaration while other declarations were pending")
        end

        declarations = (t[owner] ||= [])
        type = annotation.class

        if !type.repeatable? && declarations.any? { |p| p.annotation.instance_of?(type) }
          t.delete(owner)

          raise DuplicateAnnotation, "#{owner.inspect}: #{annotation.class.short_name} declared twice " \
                                     "for one method (it is not repeatable); pending declarations cleared"
        end
        declarations << PendingDeclaration.new(annotation, location)
        nil
      end

      # @param owner [Module]
      # @return [Array<PendingDeclaration>] the owner's declarations (removed)
      def take(owner)
        t = table
        return NONE if t.empty?

        t.delete(owner) || NONE
      end

      # @param owner [Module]
      # @return [Array<PendingDeclaration>] the owner's declarations (not removed)
      def peek(owner)
        t = table
        t[owner] || NONE
      end

      # @return [Hash{Module => Array<PendingDeclaration>}] every pending declaration (removed)
      def take_all
        t = table
        return {} if t.empty?

        left = t.dup
        t.clear
        left
      end

      # A constant was added to `owner`: its pending declarations can no longer attach.
      # @param owner [Module]
      # @param name [Symbol] the constant
      # @return [nil]
      # @raise [LeftoverAnnotations] when `owner` has pending declarations (they are cleared)
      def const_added(owner, name)
        return unless for?(owner)

        raise LeftoverAnnotations.new({ owner => take(owner) }, "constant #{name} added to #{owner.inspect} " \
                                                                "while declarations were pending")
      end
    end
  end
end

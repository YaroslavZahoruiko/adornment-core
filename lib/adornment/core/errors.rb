# frozen_string_literal: true

module Adornment
  # Base class of every error Adornment raises (except {UnsupportedPlatformError}).
  class Error < StandardError; end

  # A non-repeatable annotation type was declared twice for one method.
  class DuplicateAnnotation < Error; end

  # An annotation was declared for a method kind (instance or singleton) its type does not target.
  class InvalidTarget < Error; end

  # A method annotation was written with brackets (`Get["/x"]`) instead of as a call above the
  # method (`Get "/x"`).
  class TargetError < Error; end

  # An annotation's {Adornment::Annotation#validate} rejected the method it was about to attach
  # to. The validator's own exception is the `cause`; the message names the method
  # (`Owner#name` or `Owner.name`) and, when known, the declaration's location, which is also
  # the first backtrace entry. Nothing was attached.
  class DefinitionError < Error; end

  # Declarations that never attached to a method.
  class LeftoverAnnotations < Error
    # @return [Hash{Module => Array<Core::Pending::PendingDeclaration>}] frozen; leftovers per owner
    attr_reader :leftovers

    # @param leftovers [Hash{Module => Array<Core::Pending::PendingDeclaration>}]
    # @param reason [String, nil] why they can no longer attach, prepended to the message
    def initialize(leftovers, reason = nil)
      @leftovers = leftovers.transform_values { |list| list.dup.freeze }.freeze
      super(build_message(reason))
    end

    private

    # @return [String] the reason (if any), then each owner's leftovers with their locations
    def build_message(reason)
      lines = @leftovers.map do |owner, pending|
        items = pending.map { |p| "  #{p.annotation.inspect}#{" (declared at #{p.location})" if p.location}" }
        "#{owner.inspect}: #{pending.size} declaration(s) not attached to any method:\n#{items.join("\n")}"
      end
      lines.unshift("#{reason}:") if reason
      lines.join("\n")
    end
  end

  # The bare-constant lint found possible mistakes and ran with `lint: :error`.
  class LintError < Error
    # @return [Array<Adornment::Core::Lint::Diagnostic>]
    attr_reader :diagnostics

    # @param diagnostics [Array<Adornment::Core::Lint::Diagnostic>]
    def initialize(diagnostics)
      @diagnostics = diagnostics.dup.freeze
      super(diagnostics.join("\n"))
    end
  end

  # Raised by `require "adornment/core"` on Ruby engines other than CRuby.
  class UnsupportedPlatformError < LoadError; end
end

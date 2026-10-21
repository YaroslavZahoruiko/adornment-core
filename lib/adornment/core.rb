# frozen_string_literal: true

# adornment-core: the declarative metadata engine behind Adornment.
#
#   require "adornment/core"
#
#   class Traced
#     include Adornment::Annotation[]
#
#     attr_reader :span
#
#     def initialize(span: nil)
#       @span = span
#     end
#   end
#
#   class Orders
#     include Adornment[Traced]
#
#     Traced(span: "orders.fetch")
#     def fetch(id) = id
#   end
#
#   Orders.annotations_for(:fetch) # => [#<Traced span="orders.fetch">]
#
# This file is the public facade: every top-level `Adornment.*` method is declared here and
# delegates to an internal component under `Adornment::Core`. The supported surface is this
# facade, the owner API ({Adornment::Core::Target}, {Adornment::Core::Reflection}), the records
# and errors listed in the README. Everything else under `Adornment::Core` is internal.

require_relative "core/version"
require_relative "core/errors"

unless RUBY_ENGINE == "ruby"
  raise Adornment::UnsupportedPlatformError,
        "adornment-core requires CRuby (MRI); #{RUBY_ENGINE} #{RUBY_ENGINE_VERSION} is not supported"
end

require_relative "core/immutable"
require_relative "core/private/state"
require_relative "core/private/site"
require_relative "core/private/utils"
require_relative "core/private/pending"
require_relative "core/private/attachment"
require_relative "core/private/query"
require_relative "core/private/annotation_methods"
require_relative "core/reflection"
require_relative "core/annotation"
require_relative "core/hooks"
require_relative "core/base"

# Annotations for Ruby methods: types, declarations above `def`, reflection and verification.
# `Adornment[...]`, {Adornment::Annotation} and the errors live here; the owner API and records
# live under {Adornment::Core}.
module Adornment
  class << self
    # @!group Activation

    # The recommended activation: `include Adornment[Traced, Cached]`, `include Adornment[Trace:
    # Traced]` (an alias names the declaration method), or `include Adornment[]` (no declaration
    # methods; declare with `adorn`).
    #
    # @param types [Array<Class>] annotation types; each declaration method is named after its
    #   type (`Traced(...)`)
    # @param aliases [Hash{Symbol => Class}] declaration method name => annotation type
    # @return [Adornment::Core::Base] a module whose inclusion activates the includer
    # @raise [ArgumentError] for a class that is not an annotation type
    def [](*types, **aliases)
      Core::Base.new(types, aliases)
    end

    # @param owner [Object]
    # @return [Boolean] whether `owner` is an activated class or module (it or an ancestor used
    #   `include Adornment[...]` or `extend Adornment::Core::Target`)
    def activated?(owner)
      Core::Attachment.activated?(owner)
    end

    # @!group Discovery

    # Every registered class or module with its own methods annotated with `type`: the defining
    # owners, not subclasses or includers that inherit those methods (ask those with
    # `Owner.annotated_with`).
    #
    # @param type [Class] an annotation type; annotations match with `is_a?(type)`
    # @param singleton [Boolean] look at singleton methods
    # @return [Hash{Module => Hash{Symbol => Annotation}}] frozen; for repeatable types each value
    #   is a frozen Array of annotations
    # @raise [ArgumentError] when `type` is not an annotation type
    def annotated_with(type, singleton: false)
      Core::Utils.check_type!(type)
      side = singleton ? :singleton : :instance
      result = {}
      Core::Registry.owners.each do |owner|
        methods = {}
        mod = singleton ? owner.singleton_class : owner
        Core::State.of(owner)&.entries(side)&.each do |name, annotations|
          found = annotations.select { |a| a.is_a?(type) }
          next if found.empty? || !Core::Query.own?(mod, name) # removed since

          methods[name] = type.repeatable? ? found.freeze : found.first
        end
        result[owner] = methods.freeze if methods.any?
      end
      result.freeze
    end

    # @return [Array<Module>] the registered (activated), still reachable owners. The registry
    #   holds owners weakly.
    def registered_owners
      Core::Registry.owners
    end

    # @!group Verification and diagnostics

    # Raises one aggregated error for every declaration still pending in the current fiber (and
    # clears them), and runs the lint over the registered, reachable owners.
    #
    # @param lint [:warn, :error, false] how to run the bare-constant lint: print its diagnostics,
    #   raise them, or skip it
    # @return [nil]
    # @raise [Adornment::LeftoverAnnotations] for declarations that never attached
    # @raise [Adornment::LintError] with `lint: :error`, when the lint finds something
    # @raise [ArgumentError] for any other `lint:` value
    def verify_all!(lint: :warn)
      unless [:warn, :error, false].include?(lint)
        raise ArgumentError, "lint: must be :warn, :error or false, got #{lint.inspect}"
      end

      owners = Core::Registry.owners
      leftovers = Core::Pending.take_all
      diagnostics = lint ? Core::Lint.run(owners) : []
      diagnostics.each { |d| warn("adornment: #{d}") } if lint == :warn
      raise LeftoverAnnotations, leftovers unless leftovers.empty?
      raise LintError, diagnostics if lint == :error && !diagnostics.empty?

      nil
    end

    # Runs the heuristic bare-constant lint.
    #
    # @param targets [Array<Module, String>] registered owners or file paths
    # @return [Array<Adornment::Core::Lint::Diagnostic>]
    # @raise [LoadError] when Prism cannot be loaded
    def lint(*targets)
      Core::Lint.run(targets.flatten)
    end

    # Removes an owner from global discovery and verification (idempotent) and drops its pending
    # declarations. Its hooks stay installed and its metadata stays readable through
    # its own reflection API; activating it again registers it again.
    #
    # @param owner [Module]
    # @return [nil]
    def unregister(owner)
      Core::Registry.unregister(owner)
      Core::Pending.take(owner)
      nil
    end

    # @!group Utilities for extension gems

    # The freezing rule of annotation values: Array, Hash, Set and String values are copied and
    # deep-frozen (the argument is never mutated); other objects are returned as they are.
    #
    # @param value [Object]
    # @return [Object] a deep-frozen copy, or `value` itself when it is already deeply immutable or
    #   not a container or String
    def immutable_copy(value)
      Core::Immutable.copy(value)
    end

    # @!endgroup

    private

    def append_features(_base)
      raise ArgumentError, "include Adornment[...] (with the annotation types), not bare Adornment: " \
                           "a bare include would leak Adornment's constants into your constant lookup"
    end

    def prepend_features(_base)
      raise ArgumentError, "use include Adornment[...], not prepend Adornment"
    end

    def extend_object(_base)
      raise ArgumentError, "use include Adornment[...] or extend Adornment::Core::Target, not extend Adornment"
    end
  end

  # The annotation engine. The owner API ({Base}, {Target}, {Reflection}), the records
  # ({Declaration}, {Pending::PendingDeclaration}, {Site}, {Lint::Diagnostic}), {Lint} and
  # {VERSION} are public; everything marked `@api private` is internal and may change in any
  # release.
  module Core
    # Loaded on first use: the lint (which parses source with Prism) is not needed to declare or
    # reflect on annotations.
    autoload :Lint, File.expand_path("core/diagnostics/lint", __dir__)
  end
end

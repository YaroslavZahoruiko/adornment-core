# frozen_string_literal: true

require "open3"
require "rbconfig"

module SpecHelpers
  LIB = File.expand_path("../../lib", __dir__)

  extend self

  # Drops every pending declaration of the current fiber (cleanup after failures).
  # Test-only use of an internal module.
  def force_idle! = Adornment::Core::Pending.take_all

  def idle? = Adornment::Core::Pending.empty?

  def watching?(owner) = Adornment::Core::Pending.for?(owner)

  # Clears leftovers of every registered owner, so examples that call Adornment.verify_all! do
  # not see state left by other (possibly failing) examples.
  def drain_global_leftovers!
    Adornment.verify_all!(lint: false)
  rescue Adornment::LeftoverAnnotations
    nil
  end

  # An anonymous annotation type: a class including `Adornment::Annotation[**policies]`, with an
  # attr_reader per field and an initializer that takes the `positional` fields positionally (in
  # field order) and the others as keywords; fields in `defaults` are optional. The block is
  # evaluated as its body afterwards (it may redefine the initializer).
  def annotation_type(*fields, positional: [], defaults: {}, **policies, &body)
    Class.new do
      include(Adornment::Annotation[**policies])

      const_set(:DEFAULTS, defaults.freeze)
      attr_reader(*fields)

      unless fields.empty?
        params = fields.sort_by { |f| positional.include?(f) ? 0 : 1 }.map do |f|
          default = defaults.key?(f) ? "DEFAULTS[:#{f}]" : nil
          if positional.include?(f)
            default ? "#{f} = #{default}" : f.to_s
          else
            default ? "#{f}: #{default}" : "#{f}:"
          end
        end
        class_eval <<~RUBY, __FILE__, __LINE__ + 1
          def initialize(#{params.join(', ')})              # def initialize(name, size: DEFAULTS[:size])
            #{fields.map { |f| "@#{f} = #{f}" }.join('; ')} #   @name = name; @size = size
          end                                              # end
        RUBY
      end
      class_eval(&body) if body
    end
  end

  # An activated anonymous class; the block is evaluated as its body.
  def activated_class(superclass = Object, types: [SpecTypes::Meta, SpecTypes::Tag], &body)
    Class.new(superclass) do
      include Adornment[*types]

      class_eval(&body) if body
    end
  end

  def activated_module(types: [SpecTypes::Meta, SpecTypes::Tag], &body)
    Module.new do
      include Adornment[*types]

      module_eval(&body) if body
    end
  end

  def own(owner, name, singleton: false) = owner.own_annotations_for(name, singleton: singleton)

  def declare_tag(owner, name = "t") = owner.adorn(SpecTypes::Tag.new(name: name))

  def meta(label = nil) = SpecTypes::Meta.new(label: label)

  # Runs Ruby code in a fresh process with only this gem's lib/ on the load path.
  def run_ruby(code, *flags)
    Open3.capture3(RbConfig.ruby, *flags, "-I", LIB, "-e", code)
  end

  # Objects allocated by the block (GC.stat counter; CRuby). The block runs `runs` times and the
  # smallest count is returned, so one-off allocations (inline caches, first use) do not count.
  def allocations(runs: 3)
    GC.disable
    Array.new(runs) do
      before = GC.stat(:total_allocated_objects)
      yield
      GC.stat(:total_allocated_objects) - before
    end.min
  ensure
    GC.enable
  end
end

# Namespace for keyword-defined fixture classes, so specs do not define top-level constants.
module Fx; end

# Foreign method_added hooks placed ahead of Adornment's.
module ForeignHookA
end

module ForeignHookB
  LOCK = Mutex.new
  def method_added(name) = LOCK.synchronize { super }
  def singleton_method_added(name) = LOCK.synchronize { super }
end

def with_foreign_hooks(owner)
  return owner if owner.singleton_class.include?(ForeignHookB) # a non-reentrant lock must appear once

  owner.singleton_class.prepend(ForeignHookA)
  owner.singleton_class.prepend(ForeignHookB)
  owner
end

module Fx
  class ClsParent
    def inh = 1
    def self.sinh = 1
  end
end

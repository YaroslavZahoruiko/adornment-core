# frozen_string_literal: true

# One benchmark sample of this gem's lib/, in a fresh process. Prints JSON.
#
#   ruby benchmarks/suite.rb
#
# Run it through benchmarks/compare.rb, which starts one process per sample and compares the
# medians with the recorded baseline.
require "json"

ROOT = File.expand_path("..", __dir__)

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

require_started = now
allocated_before_require = GC.stat(:total_allocated_objects)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))
require "adornment/core"
REQUIRE_MS = (now - require_started) * 1000
REQUIRE_OBJECTS = GC.stat(:total_allocated_objects) - allocated_before_require
loaded = $LOADED_FEATURES.grep(%r{/adornment}).map { |f| File.expand_path(f) }
abort "loaded adornment files outside this gem: #{loaded}" if loaded.any? { |f| !f.start_with?(ROOT) }

# The measured cases (`Bench.run`) and the classes they use.
module Bench
  # A repeatable annotation type.
  class Tag
    include Adornment::Annotation[repeatable: true]

    attr_reader :name

    def initialize(name:)
      @name = name
    end
  end

  # A non-repeatable annotation type with a keyword field.
  class Traced
    include Adornment::Annotation[]

    attr_reader :span

    def initialize(span: nil)
      @span = span
    end
  end

  # An annotation type without fields.
  class Local
    include Adornment::Annotation[]
  end

  NAMES_1K = Array.new(1_000) { |i| :"m#{i}" }.freeze
  NAMES_5K = Array.new(5_000) { |i| :"m#{i}" }.freeze
  BODY = proc { 1 }

  # The unannotated baseline for calls.
  class Plain
    def call(value) = value + 1
  end

  # A method with two annotations, for calls and reflection.
  class Annotated
    include Adornment[Traced, Tag]

    Traced(span: "x")
    Tag(name: "a")
    def call(value) = value + 1
  end

  # An annotated method that {Child} overrides.
  class Parent
    include Adornment[Traced, Tag, Local]

    Traced(span: "p")
    Tag(name: "p1")
    Local()
    def fetch = 1
  end

  # An unannotated override: strict reflection reports nothing.
  class Child < Parent
    def fetch = 2
  end

  WIDE = Class.new do
    include Adornment[Traced]

    NAMES_1K.first(100).each do |name|
      Traced(span: name.to_s)
      define_method(name, &BODY)
    end
  end

  # Runs `operation` `ops` times after a warmup; returns ns/op and allocated objects/op.
  # `setup` runs outside the timed region and its result is passed to `operation`;
  # `units` is how many measured units one operation contains (e.g. 1000 definitions).
  def self.measure(ops:, units: 1, warmup: [ops / 10, 1].max, setup: -> {}, teardown: -> (_) {}, &operation)
    warmup.times do
      context = setup.call
      operation.call(context)
      teardown.call(context)
    end
    elapsed = 0.0
    objects = 0
    ops.times do
      context = setup.call
      GC.start if units > 1
      before = GC.stat(:total_allocated_objects)
      started = now
      operation.call(context)
      elapsed += now - started
      objects += GC.stat(:total_allocated_objects) - before
      teardown.call(context)
    end
    total = ops * units
    { ns: elapsed * 1e9 / total, objects: objects.fdiv(total) }
  end

  def self.loop_measure(iterations, &block)
    3.times { block.call(1_000) } # warm (and let YJIT compile)
    GC.start
    before = GC.stat(:total_allocated_objects)
    started = now
    block.call(iterations)
    elapsed = now - started
    { ns: elapsed * 1e9 / iterations, objects: (GC.stat(:total_allocated_objects) - before).fdiv(iterations) }
  end

  def self.run
    results = {}
    results["require"] = { ns: REQUIRE_MS * 1e6, objects: REQUIRE_OBJECTS.to_f }
    # First, while the registry holds only the fixture owners (later cases create thousands of
    # classes, and how many are still alive depends on GC and JIT history).
    GC.start
    owners = Adornment.registered_owners.size
    results["reflection: Adornment.annotated_with (global, #{owners} owners)"] =
      loop_measure(20_000) { |n| n.times { Adornment.annotated_with(Traced) } }

    results["activation (class + include Adornment[...])"] = measure(ops: 2_000) do
      Class.new { include Adornment[Traced, Tag] }
    end

    results["definition: plain class (baseline)"] = measure(ops: 20, units: 1_000, setup: -> { Class.new }) do |k|
      NAMES_1K.each { |n| k.define_method(n, &BODY) }
    end
    results["definition: activated, unannotated"] = measure(ops: 20, units: 1_000, setup: lambda {
      Class.new do
        include Adornment[Traced]
      end
    }) do |k|
      NAMES_1K.each { |n| k.define_method(n, &BODY) }
    end
    results["definition: activated subclass, unannotated"] = measure(
      ops: 20, units: 1_000, setup: -> { Class.new(Class.new { include Adornment[Traced] }) }
    ) do |k|
      NAMES_1K.each { |n| k.define_method(n, &BODY) }
    end

    results["declaration (repeatable, queued)"] = measure(
      ops: 20, units: 1_000, setup: -> { Class.new { include Adornment[Tag] } },
      teardown: lambda { |k|
        begin
          k.verify_adornments!
        rescue StandardError
          nil
        end
      }
    ) do |k|
      i = 0
      while i < 1_000
        k.Tag(name: "x")
        i += 1
      end
    end

    { 1_000 => NAMES_1K, 5_000 => NAMES_5K }.each do |count, names|
      results["declaration + definition (#{count} methods/owner)"] = measure(
        ops: count == 1_000 ? 20 : 5, units: count, setup: -> { Class.new { include Adornment[Traced] } }
      ) do |k|
        names.each do |n|
          k.Traced(span: "s")
          k.define_method(n, &BODY)
        end
      end
    end

    results["redefinition of annotated methods, unannotated"] = measure(
      ops: 20, units: 1_000,
      setup: lambda {
        Class.new { include Adornment[Traced] }.tap do |k|
          NAMES_1K.each do |n|
            k.Traced(span: "s")
            k.define_method(n, &BODY)
          end
        end
      }
    ) do |k|
      NAMES_1K.each { |n| k.define_method(n, &BODY) }
    end

    results["reflection: own_annotations_for"] = loop_measure(200_000) { |n| n.times { Annotated.own_annotations_for(:call) } }
    results["reflection: annotations_for (defined once)"] = loop_measure(50_000) do |n|
      n.times do
        Annotated.annotations_for(:call)
      end
    end
    results["reflection: annotations_for (unannotated override)"] = loop_measure(20_000) do |n|
      n.times do
        Child.annotations_for(:fetch)
      end
    end
    results["reflection: annotation(name, type)"] = loop_measure(50_000) { |n| n.times { Annotated.annotation(:call, Traced) } }
    results["reflection: annotated_with (100 methods)"] = loop_measure(200) { |n| n.times { WIDE.annotated_with(Traced) } }

    plain = Plain.new
    annotated = Annotated.new
    results["call: plain method"] = loop_measure(2_000_000) do |n|
      i = 0
      while i < n
        plain.call(1)
        i += 1
      end
    end
    results["call: annotated method"] = loop_measure(2_000_000) do |n|
      i = 0
      while i < n
        annotated.call(1)
        i += 1
      end
    end

    {
      ruby: RUBY_DESCRIPTION,
      yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
      prism: (require "prism"
              Prism::VERSION),
      results: results
    }
  end
end

puts JSON.generate(Bench.run)

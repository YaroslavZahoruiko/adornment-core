# frozen_string_literal: true

# Retained memory of this gem's lib/, in a fresh process. Prints JSON.
#
#   ruby benchmarks/memory.rb
#
# Each phase is measured after a full GC as the growth of live heap slots and of
# ObjectSpace.memsize_of_all (bytes CRuby attributes to live objects, including hash and array
# buffers) since the previous phase. Run through benchmarks/memory_compare.rb.
require "json"
require "objspace"

ROOT = File.expand_path("..", __dir__)
CLASSES = Integer(ENV.fetch("CLASSES", "200"))
METHODS = Integer(ENV.fetch("METHODS", "50"))

def snapshot
  4.times { GC.start(full_mark: true, immediate_sweep: true) }
  { slots: GC.stat(:heap_live_slots), bytes: ObjectSpace.memsize_of_all }
end

phases = {}
last = snapshot
measure = lambda do |name|
  now = snapshot
  phases[name] = { slots: now[:slots] - last[:slots], bytes: now[:bytes] - last[:bytes] }
  last = now
end

$LOAD_PATH.unshift(File.join(ROOT, "lib"))
require "adornment/core"
measure.call("require")

# The annotation type of the measured workload.
class Tag
  include Adornment::Annotation[]

  attr_reader :name

  def initialize(name)
    @name = name
  end
end
OWNERS = Array.new(CLASSES) do |c|
  Class.new do
    include Adornment[Tag]

    METHODS.times do |m|
      Tag("c#{c}m#{m}")
      define_method(:"m#{m}") { m }
    end
  end
end
measure.call("#{CLASSES} classes x #{METHODS} annotated methods")

OWNERS.each { |k| METHODS.times { |m| k.annotations_for(:"m#{m}") } }
measure.call("annotations_for on every method")

OWNERS.each { |k| k.annotated_with(Tag) }
measure.call("annotated_with on every class")

Adornment.annotated_with(Tag)
measure.call("global Adornment.annotated_with")

puts JSON.generate(ruby: RUBY_DESCRIPTION, phases: phases)

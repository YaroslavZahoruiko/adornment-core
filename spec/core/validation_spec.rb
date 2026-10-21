# frozen_string_literal: true

module Fx
  # Records every site it is validated against; raises when the method name says so.
  class Checked
    include Adornment::Annotation[repeatable: true]

    SEEN = [] # rubocop:disable Style/MutableConstant

    def initialize(label = nil)
      @label = label
    end

    def validate(site)
      SEEN << { site: site, owner: site.owner, name: site.name, method: site.method,
                annotations: site.annotations, instance: site.instance?, singleton: site.singleton? }
      raise KeyError, "rejected #{site.name}" if site.name.to_s.start_with?("bad")
    end
  end

  # Not repeatable; conflicts with Exclusive siblings.
  class Solo
    include Adornment::Annotation[]

    def validate(site)
      raise ArgumentError, "Solo and Exclusive cannot be combined" if site.annotations.any?(Exclusive)
    end
  end

  class Exclusive
    include Adornment::Annotation[]
  end

  # Calls HOOK (when set) from its validator.
  class Hooked
    include Adornment::Annotation[repeatable: true]

    HOOK = [] # rubocop:disable Style/MutableConstant

    def initialize(label)
      @label = label
    end

    def validate(site) = HOOK.each { |hook| hook.call(self, site) }
  end
end

RSpec.describe "attachment-time validation" do
  before { Fx::Checked::SEEN.clear }

  def owner_with(&body)
    Class.new do
      include Adornment[Fx::Checked, Fx::Solo, Fx::Exclusive]

      class_eval(&body) if body
    end
  end

  it "gives each validator the site and the complete proposed set" do
    k = owner_with do
      Checked "a"
      Checked "b"
      def run(value) = value
    end
    expect(Fx::Checked::SEEN.size).to eq(2)
    first = Fx::Checked::SEEN.first
    expect(first.slice(:owner, :name, :instance, :singleton)).to eq(owner: k, name: :run, instance: true, singleton: false)
    expect(first[:method]).to be_a(UnboundMethod).and have_attributes(name: :run, owner: k)
    expect(first[:annotations]).to eq([Fx::Checked.new("a"), Fx::Checked.new("b")]).and be_frozen
    expect(Fx::Checked::SEEN.last[:site]).to equal(first[:site]) # one site per definition
    expect(first[:site]).not_to respond_to(:location)
  end

  it "points a failure at the declaration that failed, not the first one" do
    line = nil
    error = begin
      owner_with do
        line = __LINE__ + 1
        Exclusive()
        Solo()
        def run = 1
      end
      nil
    rescue Adornment::DefinitionError => e
      e
    end
    expect(error).to be_a(Adornment::DefinitionError)
    expect(error.message).to end_with("Solo and Exclusive cannot be combined (declared at #{__FILE__}:#{line + 1})")
    expect(error.backtrace.first).to eq("#{__FILE__}:#{line + 1}")
  end

  it "validates singleton methods with a singleton site" do
    owner_with do
      Checked "s"
      def self.run = 1
    end
    expect(Fx::Checked::SEEN.first.slice(:instance, :singleton)).to eq(instance: false, singleton: true)
  end

  it "wraps a validator failure in DefinitionError, keeping the cause and pointing at the user's line" do
    line = nil
    k = Class.new { include Adornment[Fx::Checked] }
    error = begin
      k.class_eval do
        line = __LINE__ + 1
        Checked "x"
        def bad_one = 1
      end
    rescue Adornment::DefinitionError => e
      e
    end
    expect(error).to be_a(Adornment::DefinitionError)
    expect(error.message).to eq("#{k.inspect}#bad_one: rejected bad_one (declared at #{__FILE__}:#{line})")
    expect(error.cause).to be_a(KeyError).and have_attributes(message: "rejected bad_one")
    expect(error.backtrace.first).to eq("#{__FILE__}:#{line}")
    expect(k.annotations_for(:bad_one)).to eq([]) # nothing attached
    expect(k.pending_adornments).to eq([]) # nothing left pending
  end

  it "uses Owner.method for singleton failures" do
    k = Class.new { include Adornment[Fx::Checked] }
    expect do
      k.class_eval do
        Checked()
        def self.bad = 1
      end
    end
      .to raise_error(Adornment::DefinitionError, /\A#{Regexp.escape(k.inspect)}\.bad: rejected bad/)
  end

  it "lets the method be defined again with or without annotations after a failure" do
    k = Class.new { include Adornment[Fx::Checked] }
    expect do
      k.class_eval do
        Checked "x"
        def bad_two = 1
      end
    end.to raise_error(Adornment::DefinitionError)
    k.class_eval { def bad_two = 2 }
    expect([k.new.bad_two, k.annotations_for(:bad_two)]).to eq([2, []])
    k.class_eval do
      Checked "ok"
      alias_method :fine, :bad_two
    end
    expect(k.annotations_for(:fine)).to eq([Fx::Checked.new("ok")])
  end

  it "validates explicit adorn and reused prepared instances" do
    prepared = Fx::Checked.new("shared")
    k = Class.new do
      include Adornment[]

      adorn prepared
      def one = 1
      adorn prepared, Fx::Checked.new("more")
      def two = 2
    end
    expect(k.annotations_for(:one)).to eq([prepared])
    expect(k.annotations_for(:two)).to eq([prepared, Fx::Checked.new("more")])
    expect(k.annotations_for(:two).first).to equal(prepared)
    expect(Fx::Checked::SEEN.map { |s| s[:name] }).to eq(%i[one two two])
  end

  it "rejects classes passed to adorn" do
    k = Class.new { include Adornment[] }
    expect do
      k.adorn(Fx::Checked)
    end.to raise_error(ArgumentError,
                       /Fx::Checked is an annotation type, not an instance; pass Checked\.new\(\.\.\.\)/)
    expect { k.adorn(Fx::Checked, "x") }.to raise_error(ArgumentError, /annotation type/)
    expect { k.adorn(String) }.to raise_error(ArgumentError, /expected an Adornment annotation instance/)
    expect(k.pending_adornments).to eq([])
  end

  it "detects a conflict in one declaration set, in either order" do
    expect do
      owner_with do
        Solo()
        Exclusive()
        def c = 1
      end
    end.to raise_error(Adornment::DefinitionError, /cannot be combined/)
    expect do
      owner_with do
        Exclusive()
        Solo()
        def c = 1
      end
    end.to raise_error(Adornment::DefinitionError, /cannot be combined/)
  end

  it "checks targets and duplicates before validators" do
    calls = 0
    Fx::Hooked::HOOK << -> (*) { calls += 1 }
    stub_const("OnlyInstance", Class.new(Fx::Hooked) { include Adornment::Annotation[targets: [:instance], repeatable: false] })
    k = Class.new { include Adornment[] }
    expect do
      k.class_eval do
        adorn OnlyInstance.new("a"), OnlyInstance.new("b")
        def x
          1
        end
      end
    end.to raise_error(Adornment::DuplicateAnnotation)
    expect do
      k.class_eval do
        adorn OnlyInstance.new("d")
        def self.z = 1
      end
    end.to raise_error(Adornment::InvalidTarget)
    expect(calls).to eq(0)
  ensure
    Fx::Hooked::HOOK.clear
  end
end

# frozen_string_literal: true

# Pending declarations: fiber-local, keyed by the owner (by identity), one owner at a time.
RSpec.describe "pending declarations" do
  it "are keyed by the owner, compared by identity" do
    k = activated_class
    k.adorn(SpecTypes::Meta.new)
    expect(Adornment::Core::Pending.table.keys).to eq([k])
    expect(Adornment::Core::Pending.table).to be_compare_by_identity
    k.define_method(:x) { 1 }
    expect(idle?).to be(true)
  end

  it "a declaration on another owner raises, naming the unresolved owner, and clears everything" do
    a = activated_class
    b = activated_class
    a.adorn(SpecTypes::Tag.new(name: "a"))
    expect { b.adorn(SpecTypes::Tag.new(name: "b")) }.to raise_error(Adornment::LeftoverAnnotations) { |e|
      expect(e.leftovers.keys).to eq([a])
      expect(e.message).to include("#{b.inspect} got a declaration while other declarations were pending", '"a"')
    }
    expect(idle?).to be(true)
  end

  it "tells owners apart by identity, even when they override hash and eql?" do
    alike = proc do
      define_singleton_method(:hash) { 1 }
      define_singleton_method(:eql?) { |_other| true }
    end
    a = activated_class(&alike)
    b = activated_class(&alike)
    a.adorn(SpecTypes::Tag.new(name: "a"))
    expect(Adornment::Core::Pending.for?(b)).to be(false)
    expect { b.adorn(SpecTypes::Tag.new(name: "b")) }.to raise_error(Adornment::LeftoverAnnotations) { |e|
      expect(e.leftovers.keys).to eq([a])
    }
  end

  it "a nested class with its own declaration raises" do
    expect do
      Fx.module_eval <<~RUBY, __FILE__, __LINE__ + 1
        class PendOuter
          include Adornment[SpecTypes::Traced]
          Traced(span: "x")
          remove_const(:Inner) if const_defined?(:Inner, false)
          Inner = Class.new { include Adornment[SpecTypes::Traced]; Traced(span: "inner") }
        end
      RUBY
    end.to raise_error(Adornment::LeftoverAnnotations, /PendOuter/)
    expect(idle?).to be(true)
  end

  describe "a constant added to the owner while declarations are pending" do
    it "raises for a nested class" do
      expect do
        Fx.module_eval <<~RUBY, __FILE__, __LINE__ + 1
          class PendService
            include Adornment[SpecTypes::Traced]
            Traced(span: "x")
            class Inner
            end
            def fetch = 1
          end
        RUBY
      end.to raise_error(Adornment::LeftoverAnnotations, /constant Inner added to Fx::PendService/)
      expect(Fx::PendService.annotations_for(:fetch)).to be_empty
      expect(idle?).to be(true)
    end

    it "raises for a constant assignment and a module" do
      k = activated_class
      k.adorn(SpecTypes::Meta.new)
      expect { k.const_set(:LIMIT, 1) }.to raise_error(Adornment::LeftoverAnnotations, /constant LIMIT/)
      k.adorn(SpecTypes::Meta.new)
      expect { k.class_eval("module Helpers; end", __FILE__, __LINE__) }.to raise_error(Adornment::LeftoverAnnotations, /Helpers/)
      expect(idle?).to be(true)
    end

    it "is ordinary without pending declarations" do
      k = activated_class
      k.const_set(:LIMIT, 1)
      k.adorn(SpecTypes::Meta.new)
      k.define_method(:x) { 1 }
      k.const_set(:OTHER, 2)
      expect(k.annotations_for(:x)).to eq([SpecTypes::Meta.new])
    end
  end

  it "stay pending across a body end and attach to the owner's next definition" do
    Fx.module_eval("class PendReopen; include Adornment[SpecTypes::Tag]; Tag(name: 't'); end", __FILE__, __LINE__)
    expect(Fx::PendReopen.pending_adornments.map(&:name)).to eq(["t"])
    Fx.module_eval("class PendReopen; def later = 1; end", __FILE__, __LINE__)
    expect(Fx::PendReopen.annotations_for(:later).map(&:name)).to eq(["t"])
  end

  it "a duplicate non-repeatable type clears the owner's queue" do
    k = activated_class
    k.adorn(SpecTypes::Meta.new)
    expect { k.adorn(SpecTypes::Meta.new) }.to raise_error(Adornment::DuplicateAnnotation)
    expect(idle?).to be(true)
  end

  it "Adornment.unregister drops the owner's pending declarations" do
    k = activated_class
    k.adorn(SpecTypes::Meta.new)
    Adornment.unregister(k)
    expect(idle?).to be(true)
  end

  it "are fiber-local: another fiber may declare on another owner" do
    a = activated_class
    b = activated_class
    a.adorn(SpecTypes::Tag.new(name: "main"))
    Fiber.new do
      b.adorn(SpecTypes::Tag.new(name: "fiber"))
      b.define_method(:f) { 1 }
    end.resume
    a.define_method(:m) { 1 }
    expect([a.annotations_for(:m), b.annotations_for(:f)].map { |r| r.map(&:name) }).to eq([["main"], ["fiber"]])
  end

  it "are thread-local" do
    k = activated_class
    k.adorn(SpecTypes::Meta.new)
    other = Thread.new do
      c = Class.new do
        include Adornment[SpecTypes::Tag]

        Tag(name: "t")
        def fetch = 1
      end
      [c.annotations_for(:fetch).map(&:name), Adornment::Core::Pending.empty?]
    end.value
    expect(other).to eq([["t"], true])
    k.define_method(:x) { 1 }
    expect(idle?).to be(true)
  end
end

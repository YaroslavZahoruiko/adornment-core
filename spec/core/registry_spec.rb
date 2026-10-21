# frozen_string_literal: true

RSpec.describe "registry and global verification" do
  before { drain_global_leftovers! }

  it "enumerates activated owners and reports the pending leftovers" do
    a = activated_class
    b = activated_class
    a.adorn(SpecTypes::Tag.new(name: "a"))
    expect(Adornment.registered_owners).to include(a, b)
    expect { Adornment.verify_all!(lint: false) }.to raise_error(Adornment::LeftoverAnnotations) { |e|
      expect(e.leftovers.keys).to eq([a])
    }
    expect(Adornment.verify_all!(lint: false)).to be_nil
  end

  it "registers again when an unregistered owner is activated again" do
    a = activated_class
    Adornment.unregister(a)
    a.include(Adornment[SpecTypes::Tag])
    a.adorn(SpecTypes::Tag.new(name: "again"))
    expect { Adornment.verify_all!(lint: false) }.to raise_error(Adornment::LeftoverAnnotations, /again/)
  end

  it "skips unregistered owners; unregister is idempotent" do
    a = activated_class
    a.adorn(SpecTypes::Tag.new(name: "a"))
    Adornment.unregister(a)
    Adornment.unregister(a)
    expect(Adornment.registered_owners).not_to include(a)
    expect(Adornment.verify_all!(lint: false)).to be_nil
  end

  it "registers subclasses of activated classes when they first declare" do
    parent = activated_class
    child = Class.new(parent) { def x = 1 }
    expect(Adornment.registered_owners).not_to include(child)
    child.class_eval do
      Tag(name: "c")
      def y = 1
    end
    expect(Adornment.registered_owners).to include(child)
  end

  it "does not hold activated owners strongly" do
    skip "GC timing is not deterministic enough on this platform" if ENV["ADORNMENT_SKIP_GC_SPEC"]
    before = Adornment.registered_owners.size
    -> { 200.times { Class.new { include Adornment[SpecTypes::Tag] } } }.call
    4.times { GC.start(full_mark: true, immediate_sweep: true) }
    expect(Adornment.registered_owners.size).to be < before + 200
  end

  it "reports activation publicly" do
    parent = activated_class
    expect(Adornment.activated?(parent)).to be(true)
    expect(Adornment.activated?(Class.new(parent))).to be(true)
    expect(Adornment.activated?(Class.new)).to be(false)
    expect(Adornment.activated?(Object.new)).to be(false)
  end

  it "validates the lint option" do
    expect { Adornment.verify_all!(lint: :loud) }.to raise_error(ArgumentError)
  end
end

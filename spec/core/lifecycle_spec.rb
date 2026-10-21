# frozen_string_literal: true

# Reload, unregister and release of owner references.
RSpec.describe "owner lifecycle" do
  def collectable?(&build)
    refs = ObjectSpace::WeakMap.new
    -> { 50.times { |i| refs[i] = build.call } }.call
    6.times { GC.start(full_mark: true, immediate_sweep: true) }
    refs.size < 50
  end

  it "releases annotated owners once the program drops them (registry and state hold none)" do
    skip "GC timing is not deterministic enough here" if ENV["ADORNMENT_SKIP_GC_SPEC"]
    expect(collectable? do
      Class.new do
        include Adornment[SpecTypes::Tag]

        Tag(name: "t")
        def fetch = 1
        annotations_for(:fetch) # reflection keeps nothing
      end
    end).to be(true)
  end

  it "unregister hides an owner from discovery but keeps its hooks and metadata" do
    k = activated_class do
      Tag(name: "before")
      def a = 1
    end
    Adornment.unregister(k)
    expect(Adornment.registered_owners).not_to include(k)
    expect(Adornment.annotated_with(SpecTypes::Tag)).not_to have_key(k)
    expect(Adornment.activated?(k)).to be(true)
    expect(k.annotations_for(:a).map(&:name)).to eq(["before"])
    k.class_eval do
      Tag(name: "after")
      def b = 1
    end
    expect(k.annotations_for(:b).map(&:name)).to eq(["after"])
    expect(Adornment.registered_owners).not_to include(k) # declaring does not re-register
    k.include(Adornment[SpecTypes::Tag]) # activating again does
    expect(Adornment.registered_owners).to include(k)
  end

  it "a reloaded class (a new constant value) starts empty; the old one keeps its own metadata" do
    Fx.module_eval("class Reloaded; include Adornment[SpecTypes::Tag]; Tag(name: 'v1'); def a = 1; end", __FILE__, __LINE__)
    old = Fx::Reloaded
    Fx.send(:remove_const, :Reloaded)
    Fx.module_eval("class Reloaded; include Adornment[SpecTypes::Tag]; def a = 2; end", __FILE__, __LINE__)
    expect(Fx::Reloaded.annotations_for(:a)).to eq([])
    expect(old.annotations_for(:a).map(&:name)).to eq(["v1"])
    Fx.send(:remove_const, :Reloaded)
  end
end

# frozen_string_literal: true

RSpec.describe "modules and includers" do
  let(:cacheable) do
    activated_module(types: [SpecTypes::Cached, SpecTypes::Meta]) do
      Cached(ttl: 5)
      def fetch = 1
      Meta(label: "m")
      def meta = 1
    end
  end

  it "activated includers see the module's declarations" do
    m = cacheable
    k = activated_class { include m }
    expect(k.annotations_for(:fetch)).to eq([SpecTypes::Cached.new(ttl: 5)])
    expect(k.declarations_for(:fetch).first).to have_attributes(owner: m, resolved: true)
  end

  it "plain class includers get reflection only: no declaration methods, no hooks" do
    m = cacheable
    k = Class.new { include m }
    expect(k.annotations_for(:fetch)).to eq([SpecTypes::Cached.new(ttl: 5)])
    expect(k.annotated_with(SpecTypes::Meta)).to eq(meta: SpecTypes::Meta.new(label: "m"))
    expect(k).not_to respond_to(:Cached)
    expect(k).not_to respond_to(:adorn)
    expect(k.singleton_class.ancestors).not_to include(Adornment::Core::Hooks, Adornment::Core::Propagation)
    expect(Adornment.activated?(k)).to be(false)
    expect(k.pending_adornments).to eq([])
  end

  it "prepending classes get reflection too" do
    m = cacheable
    k = Class.new { prepend m }
    expect(k.annotations_for(:meta)).to eq([SpecTypes::Meta.new(label: "m")])
  end

  it "extending classes get singleton-side reflection (class_methods modules)" do
    class_methods = activated_module do
      Tag(name: "build")
      def build = 1
    end
    k = Class.new { extend class_methods }
    expect(k.annotations_for(:build, singleton: true)).to eq([SpecTypes::Tag.new(name: "build")])
    expect(k).not_to respond_to(:Tag)
  end

  it "transitive class includers get reflection" do
    m = cacheable
    middle = Module.new { include m }
    k = Class.new { include middle }
    expect(middle.annotations_for(:fetch)).to eq([SpecTypes::Cached.new(ttl: 5)])
    expect(k.annotations_for(:fetch)).to eq([SpecTypes::Cached.new(ttl: 5)])
    expect(middle).not_to respond_to(:Cached)
  end
end

# frozen_string_literal: true

RSpec.describe "annotation immutability" do
  let(:tag) { annotation_type(:name) }

  it "freezes instances" do
    expect(tag.new(name: 1)).to be_frozen
  end

  it "stores deep-frozen copies of arrays without freezing the caller's objects" do
    list = [+"a"]
    ann = tag.new(name: list)
    expect(ann.name).to be_frozen
    expect(ann.name.first).to be_frozen
    expect(list).not_to be_frozen
    expect(list.first).not_to be_frozen
    list << "b"
    expect(ann.name).to eq(["a"])
  end

  it "copies hashes, sets and strings recursively" do
    inner = +"x"
    value = { key: [inner, Set[+"y"]], "s" => +"t" }
    ann = tag.new(name: value)
    expect(ann.name).to be_frozen
    expect(ann.name[:key]).to be_frozen
    expect(ann.name[:key][0]).to be_frozen
    expect(ann.name[:key][1]).to be_frozen.and(eq(Set["y"]))
    expect(inner).not_to be_frozen
    expect(value).not_to be_frozen
  end

  it "keeps other objects by reference, unfrozen" do
    callable = proc { 1 }
    object = Object.new
    ann = tag.new(name: [callable, object])
    expect(ann.name[0]).to equal(callable)
    expect(ann.name[1]).to equal(object)
    expect(callable).not_to be_frozen
  end

  it "handles self-referencing containers" do
    list = []
    list << list
    ann = tag.new(name: list)
    expect(ann.name.first).to equal(ann.name)
    hash = {}
    hash[:self] = hash
    hash[:list] = [hash]
    copied = tag.new(name: hash).name
    expect([copied[:self], copied[:list].first]).to all(equal(copied))
  end

  it "applies the rules to initializer defaults (a shared frozen default is reused)" do
    shared = %w[d].freeze
    type = Class.new do
      include Adornment::Annotation[]

      attr_reader :list, :fresh

      define_method(:initialize) do |list: shared, fresh: [+"f"]|
        @list = list
        @fresh = fresh
      end
    end
    expect(type.new.list).to equal(shared)
    expect(type.new.fresh).to be_frozen
    expect(type.new.fresh.first).to be_frozen
  end

  it "freezes values produced by the initializer's normalization" do
    labels = annotation_type(:values) do
      def initialize(values: []) = (@values = values.map(&:to_s))
    end
    source = [:a, +"b"]
    ann = labels.new(values: source)
    expect(ann.values).to be_frozen.and eq(%w[a b])
    expect(ann.values).to all(be_frozen)
    expect(source).not_to be_frozen
    expect(source.last).not_to be_frozen
  end

  it "reuses values that are already deeply immutable" do
    shareable = Ractor.make_shareable(%w[a b])
    expect(tag.new(name: shareable).name).to equal(shareable)
    expect(Adornment.immutable_copy(shareable)).to equal(shareable)
  end
end

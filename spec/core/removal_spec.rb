# frozen_string_literal: true

RSpec.describe "removal and undefinition" do
  it "remove_method drops the annotations" do
    k = activated_class do
      Tag(name: "t")
      private def fetch = 1
    end
    k.send(:remove_method, :fetch)
    expect(k.own_annotations_for(:fetch)).to be_empty
    expect(k.annotations_for(:fetch)).to be_empty
  end

  # Removal is not tracked: the entry stays, hidden while the owner does not define the method.
  it "a later unannotated definition of a removed method shows the old annotations again (limitation)" do
    k = activated_class do
      Tag(name: "t")
      def fetch = 1
    end
    k.send(:remove_method, :fetch)
    expect(k.annotations_for(:fetch)).to be_empty
    k.define_method(:fetch) { 2 }
    expect(k.annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "t")])
  end

  it "removal falls through to an annotated ancestor" do
    parent = activated_class do
      Tag(name: "parent")
      def fetch = :parent
    end
    child = activated_class(parent) do
      Tag(name: "child")
      private def fetch = :child
    end
    child.send(:remove_method, :fetch)
    expect(child.new.fetch).to eq(:parent)
    expect(child.own_annotations_for(:fetch)).to be_empty
    expect(child.annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "parent")])
  end

  it "undefinition hides an annotated ancestor and reflection stops there" do
    parent = activated_class do
      Tag(name: "parent")
      Meta()
      def fetch = :parent
    end
    child = activated_class(parent) do
      Tag(name: "child")
      def fetch = :child
    end
    child.send(:undef_method, :fetch)
    expect(child.new.respond_to?(:fetch, true)).to be(false)
    expect(child.annotations_for(:fetch)).to be_empty
    expect(child.own_annotations_for(:fetch)).to be_empty
  end

  it "singleton removal" do
    k = activated_class do
      Tag(name: "s")
      def self.build = 1
    end
    k.singleton_class.send(:remove_method, :build)
    expect(k.annotations_for(:build, singleton: true)).to be_empty
  end

  it "does not touch pending declarations" do
    k = activated_class { def gone = 1 }
    k.adorn(SpecTypes::Tag.new(name: "t"))
    k.send(:remove_method, :gone)
    expect(k.pending_adornments.map(&:name)).to eq(["t"])
    expect { k.verify_adornments! }.to raise_error(Adornment::LeftoverAnnotations)
  end
end

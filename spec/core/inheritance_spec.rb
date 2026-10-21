# frozen_string_literal: true

RSpec.describe "reflection across inheritance" do
  let(:parent) do
    Class.new do
      include Adornment[SpecTypes::Traced, SpecTypes::Cached, SpecTypes::Local, SpecTypes::Tag]

      Traced(span: "p")
      Cached()
      Local()
      Tag(name: "p1")
      Tag(name: "p2")
      def fetch = 1
    end
  end

  it "reports the same annotations for an inherited method without override" do
    child = Class.new(parent)
    expect(child.annotations_for(:fetch)).to eq(parent.annotations_for(:fetch))
  end

  it "does not carry annotations into an override (strict, as in Java)" do
    child = Class.new(parent) { def fetch = 2 }
    expect(child.annotations_for(:fetch)).to be_empty
    expect(child.own_annotations_for(:fetch)).to be_empty
    expect(child.annotated_with(SpecTypes::Traced)).to be_empty
  end

  it "reports only the override's own annotations, and finds the rest with find_annotation" do
    child = Class.new(parent) do
      Traced(span: "c")
      Tag(name: "c1")
      def fetch = 2
    end
    expect(child.annotations_for(:fetch)).to eq([SpecTypes::Traced.new(span: "c"), SpecTypes::Tag.new(name: "c1")])
    expect(child.find_annotation(:fetch, SpecTypes::Traced)).to eq(SpecTypes::Traced.new(span: "c"))
    expect(child.find_annotation(:fetch, SpecTypes::Cached)).to eq(SpecTypes::Cached.new)
    expect(Class.new(child) { def fetch = 3 }.find_annotation(:fetch, SpecTypes::Local)).to eq(SpecTypes::Local.new)
  end

  it "reports provenance with declarations_for" do
    child = Class.new(parent) do
      Traced(span: "c")
      def fetch = 2
    end
    decls = child.declarations_for(:fetch)
    expect(decls.first).to have_attributes(annotation: SpecTypes::Traced.new(span: "c"), owner: child,
                                           method_name: :fetch, singleton: false, resolved: true)
    cached = decls.find { |d| d.annotation.is_a?(SpecTypes::Cached) }
    expect(cached).to have_attributes(owner: parent, resolved: false)
    expect(decls.count { |d| d.owner.equal?(parent) }).to eq(5)
  end

  it "treats a visibility change as an override" do
    child = Class.new(parent) { private :fetch }
    expect(child.annotations_for(:fetch)).to be_empty
    expect(child.find_annotation(:fetch, SpecTypes::Local)).to eq(SpecTypes::Local.new)
    expect(child.declarations_for(:fetch).first).to have_attributes(owner: parent, resolved: false)
  end

  it "stops at an undef barrier" do
    child = Class.new(parent) { undef_method :fetch }
    expect(child.annotations_for(:fetch)).to be_empty
    grandchild = Class.new(child) { def fetch = 3 }
    expect(grandchild.annotations_for(:fetch)).to be_empty
  end

  it "falls through after removal" do
    child = Class.new(parent) do
      Cached()
      def fetch = 2
    end
    child.send(:remove_method, :fetch)
    expect(child.annotations_for(:fetch)).to eq(parent.annotations_for(:fetch))
  end

  it "walks singleton ancestors for class methods" do
    base = Class.new do
      include Adornment[SpecTypes::Meta]

      Meta(label: "base")
      def self.build = 1
    end
    sub = Class.new(base)
    expect(sub.annotations_for(:build, singleton: true)).to eq([SpecTypes::Meta.new(label: "base")])
    expect(sub.declarations_for(:build, singleton: true).first).to have_attributes(owner: base, singleton: true)
  end
end

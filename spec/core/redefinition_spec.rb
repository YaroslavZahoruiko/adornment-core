# frozen_string_literal: true

RSpec.describe "redefinition" do
  it "an annotated redefinition replaces the annotations (last definition wins)" do
    k = activated_class do
      Tag(name: "old")
      def fetch = 1
    end
    k.class_eval do
      Tag(name: "new")
      def fetch = 2
    end
    expect(k.annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "new")])
  end

  it "an unannotated redefinition keeps the annotations (only a declaration replaces them)" do
    k = activated_class do
      Tag(name: "t")
      Meta()
      def fetch = 1
    end
    k.class_eval { def fetch = 3 }
    expect(k.new.fetch).to eq(3)
    expect(k.annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "t"), SpecTypes::Meta.new])
  end

  it "reopened keyword classes behave the same" do
    Fx.module_eval <<~RUBY, __FILE__, __LINE__ + 1
      class Redef
        include Adornment[SpecTypes::Tag]
        Tag(name: "old")
        def fetch = 1
      end
      class Redef
        Tag(name: "new")
        def fetch = 2
      end
    RUBY
    expect(Fx::Redef.annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "new")])
    expect(Fx::Redef.new.fetch).to eq(2)
  end

  it "new classes (reloading) start without state" do
    build = lambda {
      activated_class do
        Tag(name: "t")
        def fetch = 1
      end
    }
    a = build.call
    b = Class.new { include Adornment[SpecTypes::Tag] }
    expect(a.annotations_for(:fetch).size).to eq(1)
    expect(b.annotations_for(:fetch)).to be_empty
  end

  it "adds no methods and prepends nothing to the owner" do
    plain = Class.new { def fetch = 1 }
    k = activated_class do
      Tag(name: "t")
      def fetch = 1
    end
    expect(k.instance_methods(false)).to eq(plain.instance_methods(false))
    expect(k.ancestors.first).to equal(k)
    expect(k.instance_method(:fetch).owner).to equal(k)
  end
end

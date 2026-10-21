# frozen_string_literal: true

# An alias starts with no annotations and can be annotated like any method; it shares the
# original's signature.
RSpec.describe "aliases" do
  it "takes its own declarations; nothing is copied from the original" do
    k = activated_class do
      Tag(name: "users")
      def show(id) = id

      Tag(name: "profile")
      alias_method :profile, :show
      alias_method :plain, :show # unannotated: a plain method
    end
    expect(k.annotations_for(:show)).to eq([SpecTypes::Tag.new(name: "users")])
    expect(k.annotations_for(:profile)).to eq([SpecTypes::Tag.new(name: "profile")])
    expect(k.annotations_for(:plain)).to eq([])
    expect(k.annotated_with(SpecTypes::Tag).keys).to eq(%i[show profile])
    expect(k.new.profile(1)).to eq(1)
  end

  it "works for the alias keyword, singleton aliases and subclasses" do
    parent = activated_class do
      def show = 1
      def self.build = 1
    end
    k = Class.new(parent) do
      Tag(name: "kw")
      alias_method :kw, :show
      Meta(label: "singleton")
      class << self
        alias_method :make, :build
      end
      Tag(name: "after")
      def after = 1
    end
    expect(k.annotations_for(:kw)).to eq([SpecTypes::Tag.new(name: "kw")])
    expect(k.annotations_for(:make, singleton: true)).to eq([SpecTypes::Meta.new(label: "singleton")])
    expect(k.annotations_for(:after)).to eq([SpecTypes::Tag.new(name: "after")])
  end
end

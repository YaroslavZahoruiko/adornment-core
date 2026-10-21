# frozen_string_literal: true

# Definition forms the README lists beyond the legacy suite.
RSpec.describe "more definition forms" do
  def tags(owner, name, singleton: false) = own(owner, name, singleton: singleton).map(&:name)

  it "protected def and define_singleton_method take declarations" do
    k = activated_class do
      Tag(name: "p")
      protected def prot = 1
      Tag(name: "s")
      define_singleton_method(:built) { 1 }
    end
    expect(tags(k, :prot)).to eq(["p"])
    expect(k.protected_method_defined?(:prot)).to be(true)
    expect(tags(k, :built, singleton: true)).to eq(["s"])
  end

  it "class << self bodies declare on the singleton side through adorn" do
    k = activated_class
    k.singleton_class.class_eval do
      k.adorn(SpecTypes::Tag.new(name: "inner"))
      def inner = 1
    end
    expect(tags(k, :inner, singleton: true)).to eq(["inner"])
  end

  it "repeatable declarations keep order across declaration methods and adorn" do
    k = activated_class do
      Tag(name: "1")
      adorn SpecTypes::Tag.new(name: "2"), SpecTypes::Meta.new(label: "m")
      Tag(name: "3")
      def fetch = 1
    end
    expect(k.annotations_for(:fetch).map { |a| a.respond_to?(:name) ? a.name : a.label }).to eq(%w[1 2 m 3])
  end
end

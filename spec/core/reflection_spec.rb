# frozen_string_literal: true

RSpec.describe "reflection" do
  let(:service) do
    Class.new do
      include Adornment[SpecTypes::Traced, SpecTypes::Cached, SpecTypes::Tag]

      Traced(span: "service.fetch")
      Cached(ttl: 30)
      def fetch = 1
      Tag(name: "a")
      Tag(name: "b")
      def tagged = 1
      def plain = 1
    end
  end

  it "reads annotations_for, annotation and annotated_with" do
    expect(service.annotations_for(:fetch))
      .to eq([SpecTypes::Traced.new(span: "service.fetch"), SpecTypes::Cached.new(ttl: 30)])
    expect(service.annotation(:fetch, SpecTypes::Cached)).to eq(SpecTypes::Cached.new(ttl: 30))
    expect(service.annotated_with(SpecTypes::Traced)).to eq(fetch: SpecTypes::Traced.new(span: "service.fetch"))
  end

  it "uses arrays for repeatable types and rejects annotation() for them" do
    expect(service.annotated_with(SpecTypes::Tag))
      .to eq(tagged: [SpecTypes::Tag.new(name: "a"), SpecTypes::Tag.new(name: "b")])
    expect { service.annotation(:tagged, SpecTypes::Tag) }.to raise_error(ArgumentError, /repeatable/)
  end

  it "filters by type and returns frozen results" do
    expect(service.annotations_for(:fetch, SpecTypes::Cached)).to eq([SpecTypes::Cached.new(ttl: 30)])
    expect(service.annotations_for(:fetch)).to be_frozen
    expect(service.annotations_for(:plain)).to be_empty.and be_frozen
    expect(service.annotated_with(SpecTypes::Traced)).to be_frozen
    expect(service.declarations_for(:fetch)).to be_frozen
    expect(service.annotation(:plain, SpecTypes::Cached)).to be_nil
  end

  it "rejects something that is not an annotation type in annotated_with, as Adornment.annotated_with does" do
    expect { service.annotated_with(Class.new) }.to raise_error(ArgumentError, /is not an annotation type/)
  end

  it "keeps declaration order" do
    expect(service.annotations_for(:tagged).map(&:name)).to eq(%w[a b])
  end

  it "pending_adornments does not clear" do
    service.adorn(SpecTypes::Tag.new(name: "p"))
    expect(service.pending_adornments.map(&:name)).to eq(["p"])
    expect(service.pending_adornments.map(&:name)).to eq(["p"])
    expect { service.verify_adornments! }.to raise_error(Adornment::LeftoverAnnotations)
  end

  it "annotation(name, type) is annotations_for(name, type).first along every kind of chain" do
    types = [SpecTypes::Meta, SpecTypes::Traced, SpecTypes::Cached, SpecTypes::Local]
    base = Class.new do
      include Adornment[*types]

      Meta(label: "base")
      Traced(span: "base")
      Local()
      def a = 1
      Cached(ttl: 1)
      Local()
      def b = 1
      Meta(label: "s")
      def self.c = 1
      Traced(span: "u")
      def u = 1
    end
    mid = Class.new(base) do
      include Adornment[*types]

      Meta(label: "mid")
      # strict: base's Traced and Local stay on base#a
      def a = 2
      # no annotations
      def b = 2
      undef_method :u # a barrier
    end
    prepended = Module.new { def a = 3 }
    leaf = Class.new(mid) { prepend prepended }
    visibility = Class.new(base) { private :a } # an override with no annotations
    [base, mid, leaf, visibility].product(%i[a b c u x], types, [false, true]).each do |owner, name, type, singleton|
      expect(owner.annotation(name, type, singleton: singleton))
        .to equal(owner.annotations_for(name, type, singleton: singleton).first),
            "#{owner.inspect} #{name} #{type} singleton=#{singleton}"
    end
    expect(mid.annotation(:a, SpecTypes::Traced)).to be_nil
    expect(leaf.annotation(:b, SpecTypes::Cached)).to be_nil
    expect(visibility.annotation(:a, SpecTypes::Traced)).to be_nil
    expect(visibility.find_annotation(:a, SpecTypes::Traced)).to eq(SpecTypes::Traced.new(span: "base"))
  end

  it "find_annotation falls back to the nearest overridden method" do
    base = Class.new do
      include Adornment[SpecTypes::Traced, SpecTypes::Cached, SpecTypes::Tag]

      Traced(span: "base")
      Cached(ttl: 1)
      def a = 1
      Traced(span: "u")
      def u = 1
    end
    mid = Class.new(base) do
      Traced(span: "mid")
      def a = 2
      undef_method :u
    end
    leaf = Class.new(mid) { def a = 3 }
    expect(leaf.annotation(:a, SpecTypes::Traced)).to be_nil
    expect(leaf.find_annotation(:a, SpecTypes::Traced)).to eq(SpecTypes::Traced.new(span: "mid"))
    expect(leaf.find_annotation("a", SpecTypes::Cached)).to eq(SpecTypes::Cached.new(ttl: 1))
    expect(leaf.find_annotation(:a, SpecTypes::Local)).to be_nil
    expect(Class.new(mid) { def u = 3 }.find_annotation(:u, SpecTypes::Traced)).to be_nil # undef barrier
    expect(leaf.find_annotation(:missing, SpecTypes::Traced)).to be_nil
    expect { leaf.find_annotation(:a, SpecTypes::Tag) }.to raise_error(ArgumentError, /repeatable; use declarations_for/)
    expect { leaf.find_annotation(:a, Class.new) }.to raise_error(ArgumentError, /not an annotation type/)
  end

  it "accepts string names" do
    expect(service.annotations_for("fetch").size).to eq(2)
  end

  it "reports singleton methods with singleton: true" do
    k = activated_class do
      Meta(label: "s")
      def self.build = 1
    end
    expect(k.annotations_for(:build, singleton: true)).to eq([SpecTypes::Meta.new(label: "s")])
    expect(k.annotations_for(:build)).to be_empty
  end
end

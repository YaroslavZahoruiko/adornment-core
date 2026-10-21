# frozen_string_literal: true

module Fx
  # Named definitions, as users write them.
  class Route
    include Adornment::Annotation[repeatable: true]

    attr_reader :path, :verbs

    def initialize(path, verbs: [:GET])
      @path = path
      @verbs = verbs.map(&:to_sym)
    end
  end

  class ChildRoute < Route
    include Adornment::Annotation[repeatable: false]
  end
end

RSpec.describe "annotation type definitions" do
  it "are named classes configured by an included policy module" do
    expect(Fx::Route.ancestors).to include(Adornment::Annotation)
    expect(Fx::Route.ancestors[1].inspect).to eq("Adornment::Annotation[repeatable: true]")
    expect(Adornment::Annotation[].inspect).to eq("Adornment::Annotation[]")
    expect(Fx::Route.new("/u")).to be_a(Adornment::Annotation).and be_frozen
    expect([Fx::Route.repeatable?, Fx::Route.targets, Fx::Route.short_name])
      .to eq([true, %i[instance singleton], "Route"])
  end

  it "construct with Ruby's own initializer: positional, keywords, defaults and errors" do
    expect(Fx::Route.new("/u").verbs).to eq([:GET])
    expect(Fx::Route.new("/u", verbs: ["POST"]).verbs).to eq([:POST])
    expect { Fx::Route.new }.to raise_error(ArgumentError, /wrong number of arguments/)
    expect { Fx::Route.new("/u", colour: 1) }.to raise_error(ArgumentError, /unknown keyword: :colour/)
  end

  it "applies defaults: not repeatable, both sides" do
    type = annotation_type(:a)
    expect(type.adornment_policy).to eq(repeatable: false, targets: %i[instance singleton])
  end

  describe "policy validation" do
    it "rejects unknown keys, invalid values and positional arguments" do
      expect { Adornment::Annotation[colour: 1] }.to raise_error(ArgumentError, /unknown annotation polic.*colour:/)
      expect { Adornment::Annotation[positional: [:a]] }.to raise_error(ArgumentError, /unknown annotation polic.*positional:/)
      expect { Adornment::Annotation[target: :parameter] }.to raise_error(ArgumentError, /unknown annotation polic.*target:/)
      expect { Adornment::Annotation[repeatable: 1] }.to raise_error(ArgumentError, /repeatable: must be true or false/)
      expect { Adornment::Annotation[targets: []] }.to raise_error(ArgumentError, /targets: must be a non-empty subset/)
      expect { Adornment::Annotation[targets: [:constant]] }.to raise_error(ArgumentError, /targets:/)
      expect { Adornment::Annotation[:method] }.to raise_error(ArgumentError, /takes policies as keywords/)
    end

    it "freezes policy data without freezing the caller's arrays" do
      targets = [:instance]
      mod = Adornment::Annotation[targets: targets]
      expect(targets).not_to be_frozen
      expect(mod.overrides).to be_frozen
      expect(mod.overrides.values).to all(be_frozen)
    end
  end

  describe "inheritance" do
    it "merges ancestor overrides, least specific first, then defaults" do
      expect(Fx::ChildRoute.adornment_policy).to eq(repeatable: false, targets: %i[instance singleton])
      expect(Fx::ChildRoute.new("/c").path).to eq("/c")
      expect(Fx::Route.repeatable?).to be(true) # the parent is unchanged
      narrow = Class.new(Fx::Route) { include Adornment::Annotation[targets: [:instance]] }
      child = Class.new(narrow) { include Adornment::Annotation[repeatable: false] }
      expect(child.adornment_policy).to eq(repeatable: false, targets: [:instance]) # from both ancestors
    end

    it "replaces arrays instead of concatenating them" do
      narrow = Class.new(Fx::Route) { include Adornment::Annotation[targets: [:singleton]] }
      expect(narrow.targets).to eq([:singleton])
    end

    it "keeps a subclass without its own policy module an annotation type" do
      sub = Class.new(Fx::Route)
      expect(sub.repeatable?).to be(true)
      expect(sub.new("/s")).to be_a(Adornment::Annotation).and be_frozen
      expect(Adornment[Sub: sub].inspect).to include("Sub:")
    end

    it "sees a policy a superclass includes after the subclass was read" do
      parent = annotation_type
      child = Class.new(parent)
      expect(child.repeatable?).to be(false)
      parent.include(Adornment::Annotation[repeatable: true])
      expect(child.repeatable?).to be(true)
    end

    it "reads the policies of a frozen type, and declares with it" do
      type = annotation_type(:name, positional: [:name], targets: [:instance]).freeze
      expect([type.repeatable?, type.targets]).to eq([false, [:instance]])
      owner = Class.new { include Adornment[Frozen: type] }
      owner.class_eval do
        Frozen("x")
        def fetch = 1
      end
      expect(owner.annotations_for(:fetch).map(&:name)).to eq(["x"])
    end

    it "includes the shared behavior once when a subclass includes a policy module again" do
      child = Class.new(Fx::Route) { include Adornment::Annotation[repeatable: true] }
      expect(child.ancestors.count(Adornment::Annotation)).to eq(1)
      expect(child.singleton_class.ancestors.count(Adornment::Core::TypeMethods)).to eq(1)
      expect(child.new("/x", verbs: [+"get"]).verbs).to eq([:get]).and be_frozen
    end
  end

  describe "inclusion" do
    it "rejects bare inclusion and accepts explicit defaults" do
      expect { Class.new { include Adornment::Annotation } }.to raise_error(ArgumentError, /use include Adornment::Annotation\[\.\.\.\]/)
      expect { Class.new { prepend Adornment::Annotation[] } }.to raise_error(ArgumentError, /not prepend/)
      expect { Object.new.extend(Adornment::Annotation[]) }.to raise_error(ArgumentError, /not extend/)
      expect(Class.new { include Adornment::Annotation[] }.repeatable?).to be(false)
    end

    it "supports plain classes only" do
      expect do
        Module.new do
          include Adornment::Annotation[]
        end
      end.to raise_error(ArgumentError, /can only be included in a plain class/)
      expect { Data.define(:a) { include Adornment::Annotation[] } }.to raise_error(ArgumentError, /plain class/)
      expect { Struct.new(:a) { include Adornment::Annotation[] } }.to raise_error(ArgumentError, /plain class/)
    end

    it "does not accept classes that merely look like annotation types" do
      lookalike = Class.new do
        def self.repeatable? = false
        def self.targets = %i[instance singleton]
      end
      expect { Class.new { include Adornment[L: lookalike] } }
        .to raise_error(ArgumentError, /is not an annotation type; include Adornment::Annotation\[\.\.\.\]/)
      expect do
        Class.new do
          include Adornment[]

          adorn lookalike.new
        end
      end.to raise_error(ArgumentError, /expected an Adornment annotation instance/)
    end
  end

  it "renders #<TypeName field=value>" do
    stub_const("CachedT", annotation_type(:ttl, defaults: { ttl: 60 }))
    stub_const("Bare", annotation_type)
    expect(CachedT.new(ttl: 30).inspect).to eq("#<CachedT ttl=30>")
    expect(CachedT.new.to_s).to eq("#<CachedT ttl=60>")
    expect(Bare.new.inspect).to eq("#<Bare>")
    expect(annotation_type(:x).new(x: "s").inspect).to eq('#<Adornment::Annotation x="s">')
  end

  it "compare, hash and pattern-match by class and fields" do
    a = Fx::Route.new("/x")
    b = Fx::Route.new("/x", verbs: [:GET])
    expect(a).to eq(b).and eql(b)
    expect(a.hash).to eq(b.hash)
    expect({ a => 1 }[b]).to eq(1)
    expect(a).not_to eq(Fx::Route.new("/y"))
    expect(a.hash).not_to eq(Fx::Route.new("/y").hash)
    expect(a).not_to eq(Fx::ChildRoute.new("/x"))
    expect(Fx::Route.new(1)).to eq(Fx::Route.new(1.0))
    expect(Fx::Route.new(1)).not_to eql(Fx::Route.new(1.0))
    expect(a.to_h).to eq(path: "/x", verbs: [:GET])
    matched = case a
              in { path: String => path, verbs: [:GET] } then path
              end
    expect(matched).to eq("/x")
  end
end

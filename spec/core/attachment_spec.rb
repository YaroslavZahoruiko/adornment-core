# frozen_string_literal: true

RSpec.describe "attaching pending declarations" do
  def tags(owner, name, singleton: false) = own(owner, name, singleton: singleton).grep(SpecTypes::Tag).map(&:name)

  it "attaches each declaration to its own plain, endless and private definition" do
    k = activated_class do
      Tag(name: "a")
      def a; end
      Tag(name: "b")
      def b = 1
      Tag(name: "c")
      private def c = 1
    end
    expect([tags(k, :a), tags(k, :b), tags(k, :c)]).to eq([["a"], ["b"], ["c"]])
  end

  it "attaches in class_eval strings and blocks" do
    k = activated_class
    k.class_eval <<~RUBY, __FILE__, __LINE__ + 1
      Tag(name: "s")
      def s = 1
    RUBY
    k.class_eval do
      Tag(name: "b")
      def b = 1
    end
    expect([tags(k, :s), tags(k, :b)]).to eq([["s"], ["b"]])
  end

  it "keeps repeatable declarations in order" do
    k = activated_class do
      Tag(name: "a")
      Tag(name: "b")
      def fetch = 1
    end
    expect(tags(k, :fetch)).to eq(%w[a b])
  end

  it "raises DuplicateAnnotation for a non-repeatable type and clears pending" do
    k = Class.new { include Adornment[SpecTypes::Cached] }
    expect do
      k.class_eval do
        Cached(ttl: 1)
        Cached(ttl: 2)
      end
    end.to raise_error(Adornment::DuplicateAnnotation)
    expect(k.pending_adornments).to be_empty
    k.verify_adornments!
  end

  describe "targets" do
    it "raises InvalidTarget for an instance-only type on def self.x and clears pending" do
      k = Class.new { include Adornment[SpecTypes::InstanceOnly] }
      expect do
        k.class_eval do
          InstanceOnly()
          def self.build = 1
        end
      end.to raise_error(Adornment::InvalidTarget, /singleton/)
      expect(k.pending_adornments).to be_empty
      expect(k.annotations_for(:build, singleton: true)).to be_empty
    end

    it "attaches singleton-targeted types to def self.x" do
      k = activated_class do
        Tag(name: "s")
        def self.build = 1
      end
      expect(tags(k, :build, singleton: true)).to eq(["s"])
    end

    it "lets a type without targets annotate both instance and singleton methods" do
      plain = annotation_type(:span, positional: [:span])
      k = Class.new do
        include Adornment[Plain: plain]

        Plain("i")
        def run = 1
        Plain("s")
        def self.build = 1
      end
      expect(k.annotations_for(:run)).to eq([plain.new("i")])
      expect(k.annotations_for(:build, singleton: true)).to eq([plain.new("s")])
    end
  end

  describe "attr_* with pending declarations" do
    it "attr_accessor attaches to the reader only" do
      k = activated_class do
        Tag(name: "t")
        attr_accessor :a
      end
      expect(tags(k, :a)).to eq(["t"])
      expect(tags(k, :a=)).to be_empty
    end

    it "attr_writer attaches to a=" do
      k = activated_class do
        Tag(name: "t")
        attr_writer :a
      end
      expect(tags(k, :a=)).to eq(["t"])
    end

    it "several names: the first generated method takes the declaration" do
      k = activated_class do
        Tag(name: "t")
        attr_reader :a, :b
      end
      expect(tags(k, :a)).to eq(["t"])
      expect(tags(k, :b)).to be_empty
      expect(k.verify_adornments!).to be_nil
    end

    it "the singleton side works the same" do
      k = activated_class do
        Tag(name: "t")
        singleton_class.attr_reader :a, :b
      end
      expect(tags(k, :a, singleton: true)).to eq(["t"])
      expect(tags(k, :b, singleton: true)).to be_empty
    end

    it "two attr_* calls on one line are two definitions" do
      k = activated_class
      k.class_eval <<~RUBY, __FILE__, __LINE__ + 1
        Tag(name: "t")
        attr_reader :a; attr_reader :b
      RUBY
      expect(tags(k, :a)).to eq(["t"])
      expect(tags(k, :b)).to be_empty
    end

    it "an attr_* call raising part-way: Ruby's error; a method generated before it keeps the declaration" do
      k = activated_class
      expect do
        k.class_eval do
          Tag(name: "t")
          attr_reader :ok, :"bad name" # rubocop:disable Naming/MethodName -- an invalid name on purpose
        end
      end.to raise_error(NameError)
      expect(tags(k, :ok)).to eq(["t"])
      expect(k.verify_adornments!).to be_nil
    end

    it "an attr_* call raising before any method: the declaration stays pending for verify" do
      k = activated_class
      expect do
        k.class_eval do
          Tag(name: "t")
          attr_reader :"bad name" # rubocop:disable Naming/MethodName -- an invalid name on purpose
        end
      end.to raise_error(NameError)
      expect { k.verify_adornments! }.to raise_error(Adornment::LeftoverAnnotations, /name="t"/)
    end

    it "attr_* without pending declarations defines plain methods" do
      k = activated_class { attr_reader :a, :b }
      expect(k.new).to respond_to(:a, :b)
      expect(tags(k, :a)).to be_empty
    end
  end

  describe "declarations outside any body" do
    it "attach to the next definition from the same fiber" do
      k = activated_class
      k.adorn(SpecTypes::Tag.new(name: "x"))
      k.define_method(:x) { 1 }
      expect(k.annotations_for(:x).map(&:name)).to eq(["x"])
    end

    it "leftovers are found only by verify" do
      k = activated_class
      k.adorn(SpecTypes::Tag.new(name: "x"))
      expect { k.verify_adornments! }.to raise_error(Adornment::LeftoverAnnotations)
      expect(k.verify_adornments!).to be_nil
    end
  end
end

# frozen_string_literal: true

RSpec.describe "hook dispatch" do
  it "activation at two levels attaches each declaration once" do
    parent = Class.new { include Adornment[SpecTypes::Tag] }
    child = Class.new(parent) do
      include Adornment[SpecTypes::Tag]

      Tag(name: "once")
      def fetch = 1
    end
    expect(child.annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "once")])
  end

  it "prepends the hooks once per ancestry: a subclass inherits them" do
    parent = activated_class
    child = Class.new(parent) { include Adornment[SpecTypes::Tag] }
    expect(child.singleton_class.ancestors.count(Adornment::Core::Hooks)).to eq(1)
  end

  # Like any Ruby hook, a subclass's own `method_added` must call super.
  it "a subclass hook without super stops attaching; the declaration stays pending" do
    parent = activated_class
    child = Class.new(parent) do
      def self.method_added(_name) = nil
      Tag(name: "t")

      private

      def fetch = 1
    end
    expect(child.annotations_for(:fetch)).to eq([])
    expect(child.pending_adornments).to eq([SpecTypes::Tag.new(name: "t")])
    expect { child.verify_adornments! }.to raise_error(Adornment::LeftoverAnnotations)
  end

  # A subclass's own `method_added` runs before the inherited hooks, so a declaration it makes
  # before super attaches to the method being defined.
  it "a declaration made by a subclass hook before super attaches to the current definition" do
    child = Class.new(activated_class) do
      def self.method_added(name)
        Tag(name: "from_hook") if name == :first
        super
      end

      def first = 1
      def second = 2
    end
    expect(child.own_annotations_for(:first)).to eq([SpecTypes::Tag.new(name: "from_hook")])
    expect(child.own_annotations_for(:second)).to eq([])
  end

  it "a declaration made by a hook waits for the next definition (one hook copy)" do
    k = activated_class do
      def self.method_added(name)
        Tag(name: "from_hook") if name == :first
        super
      end

      def first = 1
      def second = 2
    end
    expect(k.own_annotations_for(:first)).to eq([])
    expect(k.own_annotations_for(:second)).to eq([SpecTypes::Tag.new(name: "from_hook")])
  end

  [["activated class", false], ["subclass", true]].each do |label, subclass|
    it "a hook that redefines the method with a declaration attaches it to the redefinition (#{label})" do
      k = subclass ? Class.new(activated_class) : activated_class
      k.class_eval do
        def self.method_added(name)
          if name == :fetch && !@redefined
            @redefined = true
            Tag(name: "re")
            define_method(:fetch) { 2 }
          end
          super
        end

        def fetch = 1
      end
      expect(k.new.fetch).to eq(2)
      expect(k.own_annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "re")])
      expect(k.pending_adornments).to eq([])
    end

    it "an unannotated redefinition keeps the annotations; remove_method hides them (#{label})" do
      k = subclass ? Class.new(activated_class) : activated_class
      k.class_eval do
        Tag(name: "a")
        def fetch = 1
        Tag(name: "b")
        def other = 1
      end
      expect(k.own_annotations_for(:fetch).map(&:name)).to eq(["a"])
      k.class_eval { def fetch = 2 }
      k.send(:remove_method, :other)
      expect(k.own_annotations_for(:fetch).map(&:name)).to eq(["a"])
      expect(k.own_annotations_for(:other)).to eq([])
    end
  end

  it "a visibility change in a class with a prepended override takes declarations" do
    base = Class.new { def fetch = 1 }
    override = Module.new { def fetch = super + 1 }
    k = Class.new(base) do
      prepend override
      include Adornment[SpecTypes::Tag]

      Tag(name: "t")
      private :fetch
      def other = 1
    end
    expect(k.own_annotations_for(:fetch).map(&:name)).to eq(["t"])
    expect(k.own_annotations_for(:other)).to eq([])
    expect(k.annotations_for(:fetch)).to eq([]) # the prepended override runs
  end

  it "foreign hooks behind Adornment still receive events" do
    seen = []
    foreign = Module.new do
      define_method(:method_added) do |name|
        seen << name
        super(name)
      end
    end
    k = Class.new do
      singleton_class.prepend(foreign)
      include Adornment[SpecTypes::Tag]

      Tag(name: "t")
      def fetch = 1
    end
    expect(seen).to include(:fetch)
    expect(k.annotations_for(:fetch).map(&:name)).to eq(["t"])
  end

  it "keeps an included DSL (no base, a block) working" do
    concern_like = Module.new do
      def included(base = nil, &block)
        return @included_block = block if base.nil?

        super
        base.class_eval(&@included_block) if @included_block
      end
    end
    m = Module.new do
      extend concern_like
      include Adornment[SpecTypes::Tag]

      included { def from_block = :ok }
    end
    k = Class.new { include m }
    expect(k.new.from_block).to eq(:ok)
    expect(k).to respond_to(:annotations_for)
  end
end

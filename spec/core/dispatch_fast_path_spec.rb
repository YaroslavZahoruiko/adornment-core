# frozen_string_literal: true

# Definitions with nothing pending do nothing; hooks that declare or redefine while an
# event is in flight.
RSpec.describe "hook dispatch fast path" do
  it "allocates nothing for unannotated definitions on an activated owner" do
    plain = Class.new
    activated = activated_class
    child = Class.new(activated) # inherits the hooks
    body = proc { 1 }
    [plain, activated, child].each { |k| k.define_method(:warm, &body) } # first-use allocations
    names = Array.new(200) { |i| :"m#{i}" } # interned before measuring
    counts = [plain, activated, child].map do |k|
      allocations { names.each { |name| k.define_method(name, &body) } }
    end
    expect(counts[1]).to eq(counts[0])
    expect(counts[2]).to eq(counts[0])
  end

  it "clears the pending declarations of a failing definition" do
    k = activated_class(types: [SpecTypes::InstanceOnly])
    expect do
      k.class_eval do
        InstanceOnly()
        def self.bad = 1
      end
    end.to raise_error(Adornment::InvalidTarget)
    expect(k.pending_adornments).to eq([])
    k.define_method(:a) { 1 }
    expect(k.own_annotations_for(:a)).to eq([])
  end

  [["activated class", false], ["subclass", true]].each do |label, subclass|
    describe label do
      let(:owner) { subclass ? Class.new(activated_class) : activated_class }

      # A hook defined on the owner itself runs after Adornment's (prepended) hook, so its
      # declaration waits for the next definition; a subclass's own hook runs before the inherited
      # hook, so its declaration attaches to the definition in flight.
      it "a hook that redefines without declarations, then declares" do
        k = owner
        k.define_singleton_method(:method_added) do |name|
          if name == :fetch && !@done
            @done = true
            define_method(:fetch) { 2 }
            Tag(name: "later")
          end
          super(name)
        end
        k.define_method(:fetch) { 1 }
        if subclass
          expect(k.own_annotations_for(:fetch)).to eq([SpecTypes::Tag.new(name: "later")])
          expect(k.pending_adornments).to eq([])
        else
          expect(k.own_annotations_for(:fetch)).to eq([])
          expect(k.pending_adornments).to eq([SpecTypes::Tag.new(name: "later")])
          k.define_method(:next_one) { 3 }
          expect(k.own_annotations_for(:next_one)).to eq([SpecTypes::Tag.new(name: "later")])
        end
      end

      it "an idle removal event followed by a declaration in a hook keeps the declaration pending" do
        k = owner
        k.define_method(:gone) { 1 }
        k.define_singleton_method(:method_removed) do |name|
          Tag(name: "after_removal") if name == :gone
          super(name)
        end
        k.send(:remove_method, :gone)
        expect(k.pending_adornments.map(&:name)).to eq(["after_removal"])
        k.define_method(:fresh) { 1 }
        expect(k.own_annotations_for(:fresh).map(&:name)).to eq(["after_removal"])
      end
    end
  end

  it "a declaration made in another fiber inside a hook attaches in that fiber" do
    k = activated_class
    k.define_singleton_method(:method_added) do |name|
      if name == :fetch
        Fiber.new do
          adorn(SpecTypes::Tag.new(name: "fiber"))
          define_method(:"#{name}_twin") { 2 }
        end.resume
      end
      super(name)
    end
    k.define_method(:fetch) { 1 }
    expect(k.own_annotations_for(:fetch)).to eq([])
    expect(k.own_annotations_for(:fetch_twin)).to eq([SpecTypes::Tag.new(name: "fiber")])
  end
end

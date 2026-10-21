# frozen_string_literal: true

# Internal storage contract (test-only access to Adornment::Core::State): one Hash per side at
# rest, frozen in place by a whole-side read, copied by the next write.
RSpec.describe "entry snapshots" do
  it "keeps a held snapshot unchanged by later writes and stores one Hash at rest" do
    k = activated_class do
      Tag(name: "a")
      def a = 1
    end
    state = Adornment::Core::State.of(k)
    held = state.entries(:instance)
    expect(held).to be_frozen
    expect(state.entries(:instance)).to equal(held) # no copy per read
    k.class_eval do
      Tag(name: "b")
      def b = 1
    end
    expect(held.keys).to eq([:a])
    expect(state.entries(:instance).keys).to eq(%i[a b])
    expect(Adornment.annotated_with(SpecTypes::Tag)[k].keys).to eq(%i[a b])
    k.send(:remove_method, :a) # not tracked: the entry stays, discovery hides it
    expect(state.entries(:instance).keys).to eq(%i[a b])
    expect(Adornment.annotated_with(SpecTypes::Tag)[k].keys).to eq([:b])
  end
end

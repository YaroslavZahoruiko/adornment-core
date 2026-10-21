# frozen_string_literal: true

# Core never changes how a method runs: no wrappers, no replacement, no per-call work.
RSpec.describe "execution contract" do
  let(:plain) { Class.new { def call(value) = value + 1 } }
  let(:annotated) do
    Class.new do
      include Adornment[SpecTypes::Traced, SpecTypes::Tag]

      Traced(span: "x")
      Tag(name: "t")
      def call(value) = value + 1
    end
  end

  it "keeps the defined method itself: same owner, source and arity, nothing prepended" do
    m = annotated.instance_method(:call)
    expect(m.owner).to equal(annotated)
    expect(m.source_location).to eq([__FILE__, __LINE__ - 7])
    expect(annotated.ancestors.first).to equal(annotated)
    expect(annotated.instance_methods(false)).to eq([:call])
  end

  it "adds no allocations to calls of annotated methods" do
    p_obj = plain.new
    a_obj = annotated.new
    2.times do
      p_obj.call(1)
      a_obj.call(1)
    end
    expect(allocations { 10_000.times { a_obj.call(1) } }).to eq(allocations { 10_000.times { p_obj.call(1) } })
  end

  it "runs no Adornment code during calls" do
    a_obj = annotated.new
    calls = []
    trace = TracePoint.new(:call, :c_call) { |tp| calls << tp.defined_class if tp.defined_class.to_s.include?("Adornment") }
    trace.enable { 100.times { a_obj.call(1) } }
    expect(calls).to eq([])
  end
end

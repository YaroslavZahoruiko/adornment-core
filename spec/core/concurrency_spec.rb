# frozen_string_literal: true

RSpec.describe "concurrency" do
  it "readers see frozen, consistent snapshots during redefinition" do
    k = activated_class do
      Tag(name: "old")
      def fetch = 1
    end
    old = [SpecTypes::Tag.new(name: "old")]
    new = [SpecTypes::Tag.new(name: "n1"), SpecTypes::Tag.new(name: "n2")]
    stop = false
    seen = []
    reader = Thread.new do
      until stop
        r = k.annotations_for(:fetch)
        seen << r unless r.frozen? && [old, new, []].include?(r)
      end
    end
    200.times do |i|
      if i.even?
        k.class_eval do
          Tag(name: "n1")
          Tag(name: "n2")
          def fetch = 2
        end
      else
        k.class_eval do
          Tag(name: "old")
          def fetch = 1
        end
      end
    end
    stop = true
    reader.join
    expect(seen).to be_empty
  end

  it "isolates pending declarations per fiber" do
    k = activated_class
    fiber = Fiber.new do
      k.adorn(SpecTypes::Tag.new(name: "fiber"))
      Fiber.yield
      k.define_method(:there) { 1 }
    end
    fiber.resume
    k.define_method(:here) { 1 }
    expect(k.annotations_for(:here)).to be_empty
    expect(k.pending_adornments).to be_empty
    fiber.resume
    expect(k.annotations_for(:there).map(&:name)).to eq(["fiber"])
  end

  it "defines 8x100 annotated methods in parallel without losing any" do
    k = activated_class
    threads = Array.new(8) do |t|
      Thread.new do
        Fiber.new do
          100.times do |i|
            k.adorn(SpecTypes::Tag.new(name: "#{t}-#{i}"))
            k.define_method(:"m_#{t}_#{i}") { 1 }
          end
        end.resume
        Adornment::Core::Pending.empty?
      end
    end
    expect(threads.map(&:value)).to all(be(true))
    8.times do |t|
      100.times do |i|
        expect(k.own_annotations_for(:"m_#{t}_#{i}")).to eq([SpecTypes::Tag.new(name: "#{t}-#{i}")])
      end
    end
  end
end

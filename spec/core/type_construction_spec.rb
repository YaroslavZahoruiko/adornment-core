# frozen_string_literal: true

RSpec.describe "type construction" do
  it "is Ruby's own: declaration methods and brackets call new, which runs the initializer" do
    calls = []
    type = Class.new do
      include Adornment::Annotation[]

      define_method(:initialize) do |*args, **kwargs|
        calls << [args, kwargs]
        @args = args
      end
    end
    k = Class.new { include Adornment[T: type] }
    k.class_eval do
      T(1, a: 2)
      def x = 1
    end
    expect(calls).to eq([[[1], { a: 2 }]])
  end

  it "reports wrong arguments with Ruby's errors" do
    route = annotation_type(:methods, :path, :status, positional: %i[methods path], defaults: { status: 200 })
    expect(route.new(%i[get], "/x").status).to eq(200)
    expect { route.new(%i[get]) }.to raise_error(ArgumentError, /wrong number of arguments \(given 1, expected 2\)/)
    expect { route.new(%i[get], "/x", colour: 1) }.to raise_error(ArgumentError, "unknown keyword: :colour")
    expect { route.new(%i[get], "/x", "extra") }.to raise_error(ArgumentError, /wrong number of arguments/)
    k = Class.new { include Adornment[R: route] }
    expect { k.R(%i[get]) }.to raise_error(ArgumentError, /wrong number of arguments/)
    expect(k.pending_adornments).to eq([])
  end

  it "sees a redefined initializer at once" do
    type = annotation_type(:size)
    expect { type.new }.to raise_error(ArgumentError, /missing keyword: :size/)
    type.class_eval { def initialize(size: 5) = (@size = size) }
    expect(type.new.size).to eq(5)
  end

  it "keeps an instance its initializer froze as it is" do
    type = Class.new do
      include Adornment::Annotation[]

      attr_reader :list

      def initialize(list)
        @list = list
        freeze
      end
    end
    list = [+"a"]
    expect(type.new(list).list).to equal(list) # the author took over freezing
  end

  describe "brackets" do
    it "are prohibited for method annotations" do
      stub_const("Route", annotation_type(:path, positional: [:path]))
      expect do
        Route["/x"]
      end.to raise_error(Adornment::TargetError,
                         'Route is a method annotation; write it as a call above the method: `Route("/x")`')
    end
  end

  it "exposes short_name" do
    stub_const("Obs", Module.new)
    Obs.const_set(:Traced, annotation_type(:name))
    expect(Obs::Traced.short_name).to eq("Traced")
    expect(annotation_type.short_name).to start_with("#<Class:")
  end

  describe "Adornment.immutable_copy" do
    it "deep-freezes copies of the documented containers and keeps other objects" do
      object = Object.new
      source = { list: [+"a", Set[+"b"]], object: object }
      copy = Adornment.immutable_copy(source)
      expect(copy).to eq(source).and be_frozen
      expect(copy[:list]).to be_frozen
      expect(copy[:object]).to equal(object)
      expect(source).not_to be_frozen
    end
  end
end

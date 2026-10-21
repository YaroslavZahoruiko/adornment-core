# frozen_string_literal: true

module Fx
  # Ordinary per-parameter metadata of an extension: core knows nothing about it.
  Arg = Data.define(:type, :default) do
    def initialize(type:, default: nil) = super
  end
end

# Core has only method annotations. An extension that needs per-parameter metadata keeps its own
# value objects inside one of its method annotations and interprets them.
RSpec.describe "extension metadata inside a method annotation" do
  it "is held by the annotation and read back with reflection" do
    stub_const("Args", annotation_type(:parameters, positional: [:parameters]))
    klass = Class.new do
      include Adornment[Args]

      Args({ id: Fx::Arg.new(type: Integer), page: Fx::Arg.new(type: Integer, default: 1) })
      def show(id:, page: 9) = [id, page]
    end
    args = klass.annotation(:show, Args)
    expect(args.parameters).to be_frozen.and eq(id: Fx::Arg.new(type: Integer), page: Fx::Arg.new(type: Integer, default: 1))
    expect(klass.instance_method(:show).parameters).to eq([%i[keyreq id], %i[key page]])
    expect(klass.new.show(id: 1)).to eq([1, 9]) # core never touches the method or its defaults
  end

  it "follows the freezing rule: containers are copied, other objects kept" do
    stub_const("Args", annotation_type(:parameters, positional: [:parameters]))
    arg = Fx::Arg.new(type: Integer)
    given = { id: arg }
    annotation = Args.new(given)
    expect(annotation.parameters).to be_frozen
    expect(given).not_to be_frozen
    expect(annotation.parameters[:id]).to equal(arg)
  end

  it "is not an annotation: method contexts reject it" do
    k = Class.new do
      include Adornment[]

      def x = 1
    end

    expect { k.adorn(Fx::Arg.new(type: Integer)) }.to raise_error(ArgumentError, /expected an Adornment annotation instance/)
    expect { Class.new { include Adornment[Fx::Arg] } }.to raise_error(ArgumentError, /is not an annotation type/)
    expect(k.annotations_for(:x)).to eq([])
  end

  it "never makes core read source files or load Prism" do
    out, err, status = run_ruby(<<~RUBY)
      require "adornment/core"
      Arg = Data.define(:type)
      class Args
        include Adornment::Annotation[]
        attr_reader :parameters
        def initialize(parameters) = (@parameters = parameters)
      end
      K = Class.new { include Adornment[Args] }
      K.class_eval("Args({ id: Arg.new(Integer) })\\ndef show(id: 1) = id", "(no file)")
      puts [K.annotation(:show, Args).parameters[:id].type, defined?(Prism) ? true : false].inspect
    RUBY
    expect(status).to be_success, err
    expect(out.strip).to eq("[Integer, false]")
  end
end

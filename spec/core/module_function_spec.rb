# frozen_string_literal: true

RSpec.describe "module_function with annotated methods" do
  it "bare module_function: the def takes the declarations; the singleton copy carries none" do
    m = activated_module do
      module_function

      Meta(label: "bare")
      def x = :x
    end
    expect(m.x).to eq(:x)
    expect(m.own_annotations_for(:x)).to eq([SpecTypes::Meta.new(label: "bare")])
    expect(m.own_annotations_for(:x, singleton: true)).to be_empty
    expect(m.verify_adornments!).to be_nil
  end

  # A module_function copy is a copy like an alias: it takes the declarations above it.
  it "an explicit module_function :x takes the declarations above it, on the singleton copy" do
    m = activated_module do
      Meta(label: "x")
      def x = :x
      Tag(name: "copy")
      module_function :x
      def after = 1
    end
    expect(m.x).to eq(:x)
    expect(m.own_annotations_for(:x)).to eq([SpecTypes::Meta.new(label: "x")])
    expect(m.own_annotations_for(:x, singleton: true)).to eq([SpecTypes::Tag.new(name: "copy")])
    expect(m.own_annotations_for(:after)).to be_empty
  end

  it "works in a module that includes an activated module" do
    a = activated_module do
      Meta(label: "a")
      def x = :x
    end
    b = Module.new do
      include a

      module_function :x
    end
    expect(b.x).to eq(:x)
    expect(b.annotations_for(:x)).to eq([]) # module_function made b's own private entry
    expect(b.find_annotation(:x, SpecTypes::Meta)).to eq(SpecTypes::Meta.new(label: "a"))
  end
end

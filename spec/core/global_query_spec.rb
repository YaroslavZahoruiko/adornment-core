# frozen_string_literal: true

RSpec.describe "Adornment.annotated_with" do
  let(:route) { annotation_type(:path, positional: [:path]) }
  let(:tag) { annotation_type(:name, repeatable: true, targets: %i[instance singleton], positional: [:name]) }

  it "finds every class and module with methods annotated with the type" do
    r = route
    users = Class.new do
      include Adornment[Route: r]

      Route("/users")
      def index = 1
      def plain = 1
      Route("/users/new")
      def new_form = 1
    end
    pages = Module.new do
      include Adornment[Route: r]

      Route("/about")
      def about = 1
    end
    other = Class.new do
      include Adornment[SpecTypes::Traced]

      Traced()
      def x = 1
    end

    expect(Adornment.annotated_with(r)).to eq(
      users => { index: r.new("/users"), new_form: r.new("/users/new") },
      pages => { about: r.new("/about") }
    )
    expect(Adornment.annotated_with(r)).not_to have_key(other)
  end

  it "lists defining owners only, not subclasses or includers that inherit the methods" do
    r = route
    parent = Class.new do
      include Adornment[Route: r]

      Route("/p")
      def show = 1
    end

    child = Class.new(parent) { def other = 1 }
    includer = Class.new do
      include(Module.new do
        include Adornment[Route: r]

        Route("/m")
        def m = 1
      end)
    end

    owners = Adornment.annotated_with(r).keys
    expect(owners).to include(parent)
    expect(owners).not_to include(child, includer)
    expect(child.annotated_with(r)).to eq(show: r.new("/p"))
  end

  it "uses arrays for repeatable types and supports singleton methods" do
    t = tag
    k = Class.new do
      include Adornment[Tag: t]

      Tag("a")
      Tag("b")
      def fetch = 1
      Tag("s")
      def self.build = 1
    end
    expect(Adornment.annotated_with(t)).to eq(k => { fetch: [t.new("a"), t.new("b")] })
    expect(Adornment.annotated_with(t, singleton: true)).to eq(k => { build: [t.new("s")] })
  end

  it "keeps annotations on an unannotated redefinition and hides removed methods" do
    r = route
    k = Class.new do
      include Adornment[Route: r]

      Route("/a")
      def a = 1
      def b = 1
    end

    expect(Adornment.annotated_with(r)).to eq(k => { a: r.new("/a") })
    k.class_eval { def a = 2 }
    expect(Adornment.annotated_with(r)).to eq(k => { a: r.new("/a") })
    k.send(:remove_method, :a)
    expect(Adornment.annotated_with(r)).to be_empty
  end

  it "matches subclasses of the type and skips unregistered owners" do
    r = route
    sub = Class.new(r)
    k = Class.new do
      include Adornment[Sub: sub]

      Sub("/s")
      def s = 1
    end

    expect(Adornment.annotated_with(r)).to eq(k => { s: sub.new("/s") })
    Adornment.unregister(k)
    expect(Adornment.annotated_with(r)).to be_empty
  end

  it "returns frozen results and rejects non-annotation types" do
    r = route
    Class.new do
      include Adornment[Route: r]

      Route("/x")
      def x = 1
    end

    result = Adornment.annotated_with(r)
    expect(result).to be_frozen
    expect(result.values).to all(be_frozen)
    expect { Adornment.annotated_with(String) }.to raise_error(ArgumentError, /not an annotation type/)
  end
end

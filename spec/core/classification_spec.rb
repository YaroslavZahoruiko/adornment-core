# frozen_string_literal: true

# Which definitions consume pending declarations, always with two foreign hooks ahead of
# Adornment's, one routing super through Mutex#synchronize.
RSpec.describe "definition classification" do
  def tags(owner, name, singleton: false)
    own(owner, name, singleton: singleton).grep(SpecTypes::Tag).map(&:name)
  end

  describe "the definition table" do
    before(:all) do
      Fx.module_eval <<~RUBY, __FILE__, __LINE__ + 1
        class ClsSubject < ClsParent
          include Adornment[SpecTypes::Tag, SpecTypes::Meta]
          with_foreign_hooks(self)

          Tag(name: "def")
          def original = 1
          Tag(name: "define_method unbound")
          define_method(:fresh, instance_method(:original))
          Tag(name: "define_method block")
          define_method(:blocky) { 1 }
          Tag(name: "alias_method")
          alias_method :aliased, :original
          def after_alias = 1
          Tag(name: "keyword alias")
          alias kw_aliased original
          def after_kw_alias = 1
          Tag(name: "attr_reader")
          attr_reader :attr
          Tag(name: "private inherited")
          private :inh
          def after_private = 1
          Tag(name: "private_class_method inherited")
          private_class_method :sinh
          def after_pcm = 1
          Tag(name: "def self")
          def self.klass_m = 1
          Tag(name: "endless")
          def endless = 1
          Tag(name: "private def")
          private def priv = 1
        end

        module ClsModule
          include Adornment[SpecTypes::Tag]
          with_foreign_hooks(self)
          module_function

          Tag(name: "bare module_function")
          def bare_mf = 1

          public

          Tag(name: "later module_function")
          def later_mf = 1
          module_function :later_mf
          def after_mf = 1
        end
      RUBY
    end

    let(:subject_class) { Fx::ClsSubject }

    {
      original: "def", fresh: "define_method unbound", blocky: "define_method block", attr: "attr_reader",
      endless: "endless", priv: "private def", aliased: "alias_method", kw_aliased: "keyword alias",
      inh: "private inherited"
    }.each do |name, construct|
      it "#{construct} => #{name} carries the declaration" do
        expect(tags(subject_class, name)).to eq([construct])
      end
    end

    it "aliases take the declaration, so the next definition does not" do
      expect(tags(subject_class, :after_alias)).to be_empty
      expect(tags(subject_class, :after_kw_alias)).to be_empty
      expect(tags(subject_class, :original)).to eq(["def"]) # the original keeps only its own
    end

    it "visibility changes of inherited methods are entries and consume" do
      expect(tags(subject_class, :sinh, singleton: true)).to eq(["private_class_method inherited"])
      expect(tags(subject_class, :after_private)).to be_empty
      expect(tags(subject_class, :after_pcm)).to be_empty
    end

    it "def self.x consumes on the singleton side" do
      expect(tags(subject_class, :klass_m, singleton: true)).to eq(["def self"])
    end

    it "module_function copies carry none of the original's annotations" do
      expect(tags(Fx::ClsModule, :bare_mf)).to eq(["bare module_function"])
      expect(tags(Fx::ClsModule, :later_mf)).to eq(["later module_function"])
      expect(tags(Fx::ClsModule, :bare_mf, singleton: true)).to be_empty
      expect(tags(Fx::ClsModule, :later_mf, singleton: true)).to be_empty
      expect(tags(Fx::ClsModule, :after_mf)).to be_empty
      expect(Fx::ClsModule.bare_mf).to eq(1)
    end
  end

  def klass(superclass = Object, &body)
    k = Class.new(superclass) { include Adornment[SpecTypes::Tag, SpecTypes::Meta] }
    with_foreign_hooks(k)
    k.class_eval(&body) if body
    k
  end

  it "R3: a fresh def below an undef barrier consumes" do
    a = Class.new { def x = 1 }
    b = Class.new(a) { undef_method :x }
    c = klass(b) do
      Tag(name: "x")
      def x = 3
    end
    expect(tags(c, :x)).to eq(["x"])
  end

  it "a visibility change over an ancestor's annotated method is a new, unannotated entry" do
    parent = klass(Fx::ClsParent) do
      Tag(name: "p")
      def inh = 2
    end
    child = klass(parent) do
      private :inh
      Tag(name: "t")
      def real = 1
    end
    expect(tags(child, :real)).to eq(["t"])
    expect(own(child, :inh)).to be_empty
    expect(child.annotations_for(:inh)).to be_empty
    expect(child.declarations_for(:inh).map { |d| d.annotation.name }).to eq(["p"])
    expect(child.new.send(:inh)).to eq(2)
  end

  it "a genuine redefinition of an inherited name consumes" do
    child = klass(Fx::ClsParent) do
      Tag(name: "t")
      def inh = 2
    end
    expect(tags(child, :inh)).to eq(["t"])
  end

  it "define_method(:inh, Parent.instance_method(:inh)) is a definition" do
    child = klass(Fx::ClsParent)
    child.class_eval do
      Tag(name: "t")
      define_method(:inh, Fx::ClsParent.instance_method(:inh))
    end
    expect(tags(child, :inh)).to eq(["t"])
  end

  it "R4: a same-line separate singleton definition consumes" do
    Fx.module_eval <<~RUBY, __FILE__, __LINE__ + 1
      module R4Mod
        include Adornment[SpecTypes::Tag]
        with_foreign_hooks(self)
        private def same = 1; Tag(name: "s"); def self.same = 2
      end
    RUBY
    expect(tags(Fx::R4Mod, :same, singleton: true)).to eq(["s"])
  end

  describe "C-method and attribute bodies (R7)" do
    it "distinct C-method bodies: the child definition consumes" do
      parent = klass(Array) { define_method(:value, Array.instance_method(:length)) }
      child = klass(parent) do
        Tag(name: "t")
        define_method(:value, Array.instance_method(:empty?))
      end
      expect(tags(child, :value)).to eq(["t"])
    end

    it "a visibility change over a C method or an attr reader consumes" do
      c_method = klass(Array) do
        Tag(name: "c")
        private :length
        def real = 1
      end
      parent = Class.new { attr_reader :a }
      attr = klass(parent) do
        Tag(name: "z")
        private :a
        def real = 1
      end
      redef = klass(parent) do
        Tag(name: "r")
        attr_reader :a
      end
      expect(tags(c_method, :length)).to eq(["c"])
      expect(tags(c_method, :real)).to be_empty
      expect(tags(attr, :a)).to eq(["z"])
      expect(tags(attr, :real)).to be_empty
      expect(tags(redef, :a)).to eq(["r"])
    end
  end

  describe "module_function copies of non-Ruby bodies (R11)" do
    it "a copy of an attr reader takes the declaration" do
      m = Module.new do
        include Adornment[SpecTypes::Tag]

        attr_reader :value

        Tag(name: "t")
        module_function :value
        def real = 1
      end
      expect(tags(m, :value, singleton: true)).to eq(["t"])
      expect(tags(m, :real)).to be_empty
    end

    it "copies of C-backed methods: the first copy takes the declaration" do
      m = Module.new do
        include Adornment[SpecTypes::Tag]

        define_method(:fmt, Kernel.instance_method(:format))
        define_method(:btw, Comparable.instance_method(:between?))
        Tag(name: "t")
        module_function :fmt, :btw
        def real = 1
      end
      expect(tags(m, :fmt, singleton: true)).to eq(["t"])
      expect(own(m, :btw, singleton: true) + own(m, :real)).to be_empty
      expect(m.fmt("%d", 7)).to eq("7")
    end

    it "a genuine singleton attr_reader on another line consumes" do
      m = Module.new do
        include Adornment[SpecTypes::Tag]

        attr_reader :value
        private :value
        Tag(name: "t")
        singleton_class.attr_reader :value
      end
      expect(tags(m, :value, singleton: true)).to eq(["t"])
    end

    it "a separately defined singleton with the same C body is a definition" do
      m = Module.new { include Adornment[SpecTypes::Tag] }
      m.send(:define_method, :fmt, Kernel.instance_method(:format))
      m.send(:private, :fmt)
      m.adorn(SpecTypes::Tag.new(name: "t"))
      m.define_singleton_method(:fmt, Kernel.instance_method(:format))
      expect(tags(m, :fmt, singleton: true)).to eq(["t"])
      expect(m.pending_adornments).to be_empty
    end
  end

  describe "same-line redefinitions (R14)" do
    it "same-line parent and child attr_reader: the child's definition consumes" do
      Fx.module_eval <<~RUBY, __FILE__, __LINE__ + 1
        class R14P; attr_reader :value; end; class R14C < R14P; include Adornment[SpecTypes::Tag]; Tag(name: "t"); attr_reader :value; end
      RUBY
      expect(tags(Fx::R14C, :value)).to eq(["t"])
    end

    it "same-line child define_method from the same C function consumes" do
      Fx.module_eval <<~RUBY, __FILE__, __LINE__ + 1
        class R14bP < Array; define_method(:v, Array.instance_method(:length)); end; class R14bC < R14bP; include Adornment[SpecTypes::Tag]; Tag(name: "t"); define_method(:v, Array.instance_method(:length)); end
      RUBY
      expect(tags(Fx::R14bC, :v)).to eq(["t"])
    end
  end

  describe "closures sharing an ISeq (R16)" do
    def helper(target, value) = target.define_method(:value) { value }

    it "a fresh closure from a shared helper is a definition" do
      parent = Class.new
      helper(parent, 1)
      child = klass(parent)
      child.adorn(SpecTypes::Tag.new(name: "t"))
      helper(child, 2)
      expect(tags(child, :value)).to eq(["t"])
      expect(child.new.value).to eq(2)
    end

    it "a module_function copy of a closure takes the declaration" do
      m = Module.new { include Adornment[SpecTypes::Tag] }
      helper(m, 1)
      m.adorn(SpecTypes::Tag.new(name: "t"))
      m.send(:module_function, :value)
      m.define_method(:real) { 1 }
      expect(tags(m, :value, singleton: true)).to eq(["t"])
      expect(tags(m, :real)).to be_empty
      expect(m.value).to eq(1)
    end

    it "a separately created singleton closure is a definition" do
      m = Module.new { include Adornment[SpecTypes::Tag] }
      helper(m, 1)
      m.send(:private, :value)
      m.adorn(SpecTypes::Tag.new(name: "t"))
      helper(m.singleton_class, 2)
      expect(tags(m, :value, singleton: true)).to eq(["t"])
      expect(m.value).to eq(2)
    end
  end
end

# frozen_string_literal: true

RSpec.describe "activation" do
  describe "include Adornment[...]" do
    it "activates the includer with declaration methods and reflection" do
      k = Class.new do
        include Adornment[SpecTypes::Traced, SpecTypes::Cached]

        Traced(span: "s")
        Cached()
        def fetch = 1
      end
      expect(k).to respond_to(:annotations_for)
      expect(k.annotations_for(:fetch).map(&:class)).to eq([SpecTypes::Traced, SpecTypes::Cached])
    end

    it "renames a type with an alias" do
      k = Class.new do
        include Adornment[Cache: SpecTypes::Cached]

        Cache(ttl: 5)
        def fetch = 1
      end
      expect(k.annotations_for(:fetch)).to eq([SpecTypes::Cached.new(ttl: 5)])
      expect(k).not_to respond_to(:Cached)
    end

    it "inspects as Adornment[...]" do
      expect(Adornment[SpecTypes::Traced, Cache: SpecTypes::Cached].inspect)
        .to eq("Adornment[SpecTypes::Traced, Cache: SpecTypes::Cached]")
    end

    it "rejects bare include, extend and prepend" do
      expect { Class.new { include Adornment } }.to raise_error(ArgumentError, /Adornment\[/)
      expect { Class.new { prepend Adornment } }.to raise_error(ArgumentError, /Adornment\[/)
      expect { Class.new { extend Adornment[SpecTypes::Traced] } }.to raise_error(ArgumentError, /include Adornment\[/)
      expect { Class.new { prepend Adornment[SpecTypes::Traced] } }.to raise_error(ArgumentError, /include Adornment\[/)
    end

    it "does not leak Adornment constants through a bare include" do
      k = Class.new
      expect { k.include(Adornment) }.to raise_error(ArgumentError)
      expect(k.ancestors).not_to include(Adornment)
    end

    it "rejects non-annotation types" do
      expect { Adornment[String] }.to raise_error(ArgumentError, /not an annotation type/)
    end
  end

  describe "extend Adornment::Core::Target + use_annotations" do
    it "scopes declaration methods to the owner and its subclasses" do
      service = Class.new do
        extend Adornment::Core::Target

        use_annotations SpecTypes::Traced
      end
      sub = Class.new(service)
      expect(service).to respond_to(:Traced)
      expect(sub).to respond_to(:Traced)
      expect(Object).not_to respond_to(:Traced)
      expect(Class.new).not_to respond_to(:Traced)
      expect(Object.private_methods).not_to include(:Traced)
    end

    it "raises for an anonymous type without an alias" do
      anon = annotation_type
      k = Class.new { extend Adornment::Core::Target }
      expect { k.use_annotations(anon) }.to raise_error(ArgumentError, /alias/)
      k.use_annotations(Anon: anon)
      expect(k).to respond_to(:Anon)
    end

    it "raises on a collision with a singleton method not defined by Adornment" do
      k = Class.new do
        extend Adornment::Core::Target

        def self.Traced = :mine
      end
      expect { k.use_annotations(SpecTypes::Traced) }.to raise_error(ArgumentError, /already exists/)
    end

    it "allows a subclass to re-declare the same names" do
      parent = Class.new { include Adornment[SpecTypes::Traced] }
      expect { Class.new(parent) { include Adornment[SpecTypes::Traced] } }.not_to raise_error
    end

    it "only activates classes and modules" do
      expect { Object.new.extend(Adornment::Core::Target) }.to raise_error(ArgumentError)
    end
  end

  describe "declaring" do
    it "rejects a block given to a declaration method" do
      k = Class.new { include Adornment[SpecTypes::Traced] }
      expect { k.Traced { nil } }.to raise_error(ArgumentError, /no block/)
      expect(k.pending_adornments).to be_empty
    end

    it "declares with parentheses, without parentheses, and with adorn" do
      k = Class.new do
        include Adornment[SpecTypes::Cached, SpecTypes::Traced]

        Cached ttl: 30
        def a = 1
        adorn SpecTypes::Traced.new(span: "x")
        def b = 1
      end
      expect(k.annotations_for(:a)).to eq([SpecTypes::Cached.new(ttl: 30)])
      expect(k.annotations_for(:b)).to eq([SpecTypes::Traced.new(span: "x")])
    end

    it "a bare constant does not declare" do
      stub_const("TracedC", SpecTypes::Traced)
      k = Class.new do
        include Adornment[TracedC]

        TracedC # rubocop:disable Lint/Void
        def fetch = 1
      end
      expect(k.annotations_for(:fetch)).to be_empty
    end

    it "adorn accepts annotation instances only" do
      k = Class.new { extend Adornment::Core::Target }
      expect { k.adorn(SpecTypes::Traced) }.to raise_error(ArgumentError)
      expect { k.adorn }.to raise_error(ArgumentError)
    end
  end
end

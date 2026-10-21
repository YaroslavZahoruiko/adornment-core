# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe "bare-constant lint" do
  around do |example|
    Dir.mktmpdir("adornment-lint") do |dir|
      @dir = dir
      example.run
    end
  end

  before { stub_const("LintTraced", annotation_type(:span, positional: [:span], defaults: { span: nil })) }

  def load_fixture(name, body)
    path = File.join(@dir, "#{name}.rb")
    File.write(path, body)
    load path
    path
  end

  it "flags a bare constant above a def, with file, line and a suggestion" do
    path = load_fixture("flagged", <<~RUBY)
      class Fx::LintFlagged
        include Adornment[LintTraced]
        LintTraced
        def fetch = 1
      end
    RUBY
    diags = Adornment.lint(Fx::LintFlagged)
    expect(diags.size).to eq(1)
    expect(diags.first).to have_attributes(path: path, line: 3, constant: "LintTraced", owner: "Fx::LintFlagged")
    expect(diags.first.to_s).to include("#{path}:3", "LintTraced()")
  end

  it "flags the full constant path of a registered type" do
    load_fixture("full_path", <<~RUBY)
      class Fx::LintFullPath
        include Adornment[SpecTypes::Traced]
        SpecTypes::Traced
        def fetch = 1
      end
    RUBY
    expect(Adornment.lint(Fx::LintFullPath).map(&:constant)).to eq(["SpecTypes::Traced"])
  end

  it "flags alias names" do
    load_fixture("alias", <<~RUBY)
      class Fx::LintAlias
        include Adornment[Tr: SpecTypes::Traced]
        Tr = 1
        Tr
        def fetch = 1
      end
    RUBY
    expect(Adornment.lint(Fx::LintAlias).map(&:constant)).to eq(["Tr"])
  end

  it "ignores unrelated constants and non-void uses" do
    load_fixture("clean", <<~RUBY)
      class Fx::LintClean
        include Adornment[LintTraced]
        Comparable
        LIST = [LintTraced]
        x = LintTraced
        LintTraced()
        def fetch = 1
      end
    RUBY
    expect(Adornment.lint(Fx::LintClean)).to be_empty
  end

  it "honours # adornment:ignore" do
    load_fixture("ignored", <<~RUBY)
      class Fx::LintIgnored
        include Adornment[LintTraced]
        LintTraced # adornment:ignore
        def fetch = 1
      end
    RUBY
    expect(Adornment.lint(Fx::LintIgnored)).to be_empty
  end

  it "does not honour the marker inside a string" do
    load_fixture("marker_in_string", <<~RUBY)
      class Fx::LintMarkerInString
        include Adornment[LintTraced]
        LintTraced; NOTE = "# adornment:ignore"
        def fetch = 1
      end
    RUBY
    expect(Adornment.lint(Fx::LintMarkerInString).map(&:line)).to eq([3])
  end

  it "accepts file paths and skips non-file sources" do
    path = load_fixture("by_path", <<~RUBY)
      class Fx::LintByPath
        include Adornment[LintTraced]
        LintTraced
        def fetch = 1
      end
    RUBY
    expect(Adornment.lint(path).size).to eq(1)
    evald = Class.new { include Adornment[LintTraced] }
    evald.class_eval("LintTraced\ndef x = 1", __FILE__, __LINE__)
    expect(Adornment.lint(evald)).to be_empty
  end

  it "is loaded only when it runs" do
    script = <<~RUBY
      require "adornment/core"
      class T; include Adornment::Annotation[]; end
      class K; include Adornment[T]; T(); def x = 1; end
      loaded = -> { $LOADED_FEATURES.any? { |f| f.end_with?("core/diagnostics/lint.rb") } }
      before = loaded.()
      Adornment.lint(K)
      puts [before, loaded.()].inspect
    RUBY
    out, err, status = run_ruby(script)
    expect(status).to be_success, err
    expect(out.strip).to eq("[false, true]")
  end

  describe "severities in verify_all!" do
    before do
      drain_global_leftovers!
      load_fixture("severity", <<~RUBY)
        class Fx::LintSeverity
          include Adornment[LintTraced]
          LintTraced
          def fetch = 1
        end
      RUBY
    end

    after { Adornment.unregister(Fx::LintSeverity) }

    it ":error raises LintError" do
      expect { Adornment.verify_all!(lint: :error) }.to raise_error(Adornment::LintError, /LintTraced/)
    end

    it ":warn (the default) warns" do
      expect { Adornment.verify_all! }.to output(/LintTraced\(\)/).to_stderr
    end

    it "false skips the lint" do
      expect { Adornment.verify_all!(lint: false) }.not_to output.to_stderr
    end
  end
end

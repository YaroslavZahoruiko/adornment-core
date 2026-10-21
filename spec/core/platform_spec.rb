# frozen_string_literal: true

require "open3"

RSpec.describe "platform check" do
  it "raises UnsupportedPlatformError (a LoadError) on other engines" do
    script = <<~RUBY
      Object.send(:remove_const, :RUBY_ENGINE)
      RUBY_ENGINE = "jruby"
      begin
        require "adornment/core"
      rescue LoadError => e
        puts [e.class, e.message].inspect
      end
    RUBY
    out, _err, status = run_ruby(script, "-W0")
    expect(status).to be_success
    expect(out).to include("Adornment::UnsupportedPlatformError", "jruby")
  end
end

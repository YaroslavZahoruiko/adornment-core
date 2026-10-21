# frozen_string_literal: true

# examples/events is a small extension (events.rb) and an application using it (app.rb); the
# extension must work through the public API only.
RSpec.describe "public-API extension example" do
  path = File.expand_path("../../examples/events/app.rb", __dir__)
  extension = File.expand_path("../../examples/events/events.rb", __dir__)

  def run_script(source)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", SpecHelpers::LIB, "-e", source)
    expect(status).to be_success, err
    out
  end

  it "uses no internal constant" do
    [extension, path].each do |file|
      expect(File.read(file)).not_to match(/Adornment::Core|Core::|instance_variable_get|__adornment/)
    end
  end

  it "runs as a script" do
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", SpecHelpers::LIB, path)
    expect(status).to be_success, err
    expect(out.lines.map(&:chomp)).to eq(
      ["receipt for order 42", "ledger entry for order 42", "ledger entry for order 7"]
    )
  end

  it "publishes events without calling Adornment" do
    out = run_script(<<~RUBY)
      require #{path.dump}
      routes = Events.compile
      calls = []
      trace = TracePoint.new(:call, :c_call) { |tp| calls << tp.defined_class.to_s if tp.defined_class.to_s.include?("Adornment") }
      result = trace.enable { Events.publish(routes, "order.paid", 1) }
      puts [result.size, calls.uniq].inspect
    RUBY
    expect(out.strip).to eq("[2, []]")
  end

  it "rejects a handler that does not take the payload, when it is defined" do
    out = run_script(<<~RUBY)
      require #{path.dump}
      begin
        Class.new do
          include Events::Handler

          On "order.paid"
          def broken = nil
        end
      rescue Adornment::DefinitionError => e
        puts e.message
      end
    RUBY
    expect(out).to include("#broken: an event handler takes the payload as its only argument")
  end
end

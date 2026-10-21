# frozen_string_literal: true

# Measures this gem's lib/ and compares it with the recorded baseline (benchmarks/baseline/).
#
#   ruby benchmarks/compare.rb                    # 7 samples, YJIT off and (if available) on
#   SAMPLES=11 JIT=off ruby benchmarks/compare.rb
#   RECORD=1 ruby benchmarks/compare.rb           # also save this run as the new baseline
#
# Each sample is one fresh process running benchmarks/suite.rb. The run (environment, raw samples,
# medians, min/max, allocations) goes to benchmarks/results/<ruby>-<jit>.json, and a Markdown
# table of baseline vs current to stdout and to benchmarks/results/<ruby>-<jit>.md. The baseline
# was measured at another time, so compare it on the same machine and treat small differences
# (a few percent, or within the spread) as noise.
require_relative "../../benchmarks/support"
extend BenchmarkSupport

require "digest"
require "time"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
SUITE = File.join(__dir__, "suite.rb")
RESULTS = File.expand_path(ENV.fetch("RESULTS", File.join(__dir__, "results")))
BASELINE = File.join(__dir__, "baseline")
SAMPLES = positive_integer("SAMPLES", 7)
RECORD = ENV["RECORD"] == "1"
JITS = jit_modes

def environment
  {
    ruby: RUBY_DESCRIPTION,
    platform: RUBY_PLATFORM,
    os: command_output("uname", "-srm"),
    cpu: cpu_name,
    cpus: command_output("sysctl", "-n", "hw.ncpu") || command_output("nproc"),
    date: Time.now.utc.iso8601,
    suite_sha256: Digest::SHA256.file(SUITE).hexdigest,
    core_lib_sha256: Digest::SHA256.hexdigest(Dir[File.join(ROOT, "lib/**/*.rb")].map { |f| File.read(f) }.join),
    samples: SAMPLES,
    methodology: "one fresh process per sample; within a process each case warms up, then runs a fixed number " \
                 "of operations with GC enabled (GC.start before each batch operation); ns and allocated " \
                 "objects (GC.stat) per unit"
  }
end

def run_sample(yjit) = json_result(SUITE, yjit: yjit)

def format_ns(nanos)
  return "-" if nanos.nil?

  if nanos >= 1e6 then format("%.2f ms", nanos / 1e6)
  elsif nanos >= 1e3 then format("%.2f µs", nanos / 1e3)
  else format("%.1f ns", nanos)
  end
end

def percent(value) = value.nil? ? "-" : format("%.0f%%", value * 100)
def number(value) = value.nil? ? "-" : format("%.2f", value)

FileUtils.mkdir_p(RESULTS)
JITS.each do |yjit|
  label = "#{RUBY_VERSION}-#{yjit ? 'yjit' : 'interp'}"
  samples = Array.new(SAMPLES) do |i|
    warn "#{label} sample #{i + 1}/#{SAMPLES}"
    run_sample(yjit)
  end
  summary = samples.first["results"].keys.to_h do |name|
    ns = samples.map { |s| s["results"].fetch(name)["ns"] }
    objects = samples.map { |s| s["results"].fetch(name)["objects"] }
    [name, { "median_ns" => median(ns), "min_ns" => ns.min, "max_ns" => ns.max,
             "spread" => (ns.max - ns.min) / median(ns), "median_objects" => median(objects) }]
  end
  data = { "environment" => environment.merge(yjit: yjit, prism: samples.first["prism"]), "summary" => summary,
           "raw" => samples.map { |s| s["results"] } }
  File.write(File.join(RESULTS, "#{label}.json"), JSON.pretty_generate(data))

  baseline_file = File.join(BASELINE, "#{label}.json")
  baseline = File.exist?(baseline_file) ? JSON.parse(File.read(baseline_file)) : nil
  base = baseline ? baseline["summary"] : {}
  recorded = baseline ? baseline.dig("environment", "date") : "none"
  lines = ["### Ruby #{RUBY_VERSION}, YJIT #{yjit ? 'on' : 'off'} (#{SAMPLES} samples; baseline recorded #{recorded})",
           "",
           "| case | baseline | current | current/baseline | baseline spread | current spread | " \
           "baseline objects | current objects |",
           "|---|---:|---:|---:|---:|---:|---:|---:|"]
  summary.each do |name, s|
    b = base[name] || {}
    ratio = b["median_ns"] && (s["median_ns"] / b["median_ns"])
    lines << "| #{name} | #{format_ns(b['median_ns'])} | #{format_ns(s['median_ns'])} | #{number(ratio)} | " \
             "#{percent(b['spread'])} | #{percent(s['spread'])} | " \
             "#{number(b['median_objects'])} | #{number(s['median_objects'])} |"
  end
  markdown = lines.join("\n")
  File.write(File.join(RESULTS, "#{label}.md"), "#{markdown}\n")
  puts markdown, ""

  next unless RECORD

  FileUtils.mkdir_p(BASELINE)
  File.write(baseline_file, JSON.pretty_generate(data))
  warn "recorded #{baseline_file}"
end

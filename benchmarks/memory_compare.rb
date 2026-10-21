# frozen_string_literal: true

# Retained memory of this gem's lib/ against the recorded baseline (benchmarks/baseline/), one
# fresh process per sample. Writes benchmarks/results/memory-<ruby>-<jit>.{json,md}.
#
#   ruby benchmarks/memory_compare.rb             # 5 samples, YJIT off and on
#   RECORD=1 ruby benchmarks/memory_compare.rb    # also save this run as the new baseline
require_relative "../../benchmarks/support"
extend BenchmarkSupport

require "fileutils"
require "time"

SAMPLES = positive_integer("SAMPLES", 5)
SCRIPT = File.join(__dir__, "memory.rb")
RESULTS = File.expand_path(ENV.fetch("RESULTS", File.join(__dir__, "results")))
BASELINE = File.join(__dir__, "baseline")
RECORD = ENV["RECORD"] == "1"

FileUtils.mkdir_p(RESULTS)
jit_modes.each do |yjit|
  raw = Array.new(SAMPLES) do
    json_result(SCRIPT, yjit: yjit)
  end
  label = "memory-#{RUBY_VERSION}-#{yjit ? 'yjit' : 'interp'}"
  phases = raw.first["phases"].keys.to_h do |phase|
    bytes = raw.map { |r| r["phases"][phase]["bytes"] / 1024.0 }
    [phase, { "kb" => median(bytes), "kb_min" => bytes.min, "kb_max" => bytes.max,
              "slots" => median(raw.map { |r| r["phases"][phase]["slots"] }) }]
  end
  data = { "ruby" => RUBY_DESCRIPTION, "yjit" => yjit, "samples" => SAMPLES, "date" => Time.now.utc.iso8601,
           "phases" => phases, "raw" => raw }
  File.write(File.join(RESULTS, "#{label}.json"), JSON.pretty_generate(data))

  baseline_file = File.join(BASELINE, "#{label}.json")
  baseline = File.exist?(baseline_file) ? JSON.parse(File.read(baseline_file)) : nil
  base = baseline ? baseline["phases"] : {}
  lines = ["### Retained memory, Ruby #{RUBY_VERSION}, YJIT #{yjit ? 'on' : 'off'} " \
           "(median of #{SAMPLES} processes; baseline recorded #{baseline ? baseline['date'] : 'none'})", "",
           "| phase (growth since the previous phase) | baseline KB | current KB | baseline live slots | current live slots |",
           "|---|---:|---:|---:|---:|"]
  phases.each do |phase, p|
    b = base[phase] || {}
    lines << format("| %<phase>s | %<base_kb>s | %<kb>.1f | %<base_slots>s | %<slots>d |",
                    phase: phase, base_kb: b["kb"] ? format("%.1f", b["kb"]) : "-", kb: p["kb"],
                    base_slots: b["slots"] || "-", slots: p["slots"])
  end
  File.write(File.join(RESULTS, "#{label}.md"), "#{lines.join("\n")}\n")
  puts lines, ""

  next unless RECORD

  FileUtils.mkdir_p(BASELINE)
  File.write(baseline_file, JSON.pretty_generate(data))
  warn "recorded #{baseline_file}"
end

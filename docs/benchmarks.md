# Benchmarks

Use this page to measure the cost of declaring and reading annotations. Run the commands
from `adornment-core/` after `bundle install`. For the overall documentation, see the
[index](../../docs/README.md).

Lower elapsed time and fewer allocated objects are better. YJIT is Ruby's optional
just-in-time compiler. The dated results are measurements of specific revisions, not
performance promises for every application. The history includes APIs that have since
been removed; use the [core guide](../README.md) for current syntax.

`benchmarks/compare.rb` measures this gem's `lib/` and compares it with the **recorded baseline**
in `benchmarks/baseline/`. Every sample is a fresh process running `benchmarks/suite.rb`.
`benchmarks/memory_compare.rb` does the same for retained memory (`benchmarks/memory.rb`).

```bash
ruby benchmarks/compare.rb                    # 7 samples, YJIT off and on, against the baseline
SAMPLES=11 JIT=off ruby benchmarks/compare.rb
ruby benchmarks/memory_compare.rb             # 5 samples, YJIT off and on
RECORD=1 ruby benchmarks/compare.rb           # also save the run as the new baseline
RECORD=1 ruby benchmarks/memory_compare.rb
```

Both drivers accept `JIT=off`, `JIT=on`, or `JIT=both` (the default), and reject
non-positive sample counts. Set `RESULTS=/tmp/core-benchmarks` to write exploratory
reports elsewhere; `RECORD=1` still updates the stored baseline. Even sample counts
use the average of the two middle values.

Files:

- `benchmarks/baseline/<ruby>-<jit>.json`, `memory-<ruby>-<jit>.json`: the recorded baseline
  (environment, summary per case, raw samples). Changed only by `RECORD=1`.
- `benchmarks/results/<ruby>-<jit>.{json,md}`, `memory-<ruby>-<jit>.{json,md}`: the latest run and
  its table against the baseline (`baseline | current | current/baseline | spread | objects`).
  Overwritten on each run.

The baseline is measured at another time than the run it is compared with, so compare on the
same machine and Ruby, and treat differences within the spread (or under about 10%) as noise.
Re-record after an intentional change once the new numbers are understood.

## Baseline (recorded 2026-10-21)

| | |
|---|---|
| Ruby | ruby 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [arm64-darwin25], Prism 1.9.0 |
| Machine | Apple M5, 10 CPUs, Darwin 25.4.0 arm64; a developer machine, not isolated from other work |
| Samples | 7 processes per JIT mode (memory: 5) |
| Identity | the JSON records SHA-256 of `suite.rb` and of this gem's `lib/` (`f3372de736ea`) |
| Code | version 0.1.0 working tree, measured with the cleaned benchmark drivers |

Timing and memory runs were performed sequentially. Dates in the JSON files are UTC;
the date above is the local date (Asia/Seoul). The result reports compare this run with
the previous baseline; the baseline JSON files now contain this run. Some timing cases
have substantial sample spread, so small differences are not reliable evidence of a change.

Only this machine and Ruby version were benchmarked. Earlier Docker checks were
correctness runs, not benchmarks.

| case | YJIT off | spread | objects | YJIT on | spread | objects |
|---|---:|---:|---:|---:|---:|---:|
| require | 1.77 ms | 28% | 1796.00 | 1.79 ms | 8% | 1796.00 |
| reflection: Adornment.annotated_with (global, 3 owners) | 16.79 µs | 8% | 107.00 | 9.88 µs | 11% | 107.00 |
| activation (class + include Adornment[...]) | 9.82 µs | 156% | 80.00 | 61.08 µs | 10% | 79.00 |
| definition: plain class (baseline) | 187.7 ns | 33% | 2.00 | 196.0 ns | 78% | 2.00 |
| definition: activated, unannotated | 272.6 ns | 5% | 2.00 | 227.9 ns | 18% | 2.00 |
| definition: activated subclass, unannotated | 274.1 ns | 26% | 2.01 | 229.1 ns | 10% | 2.01 |
| declaration (repeatable, queued) | 549.9 ns | 26% | 9.00 | 327.3 ns | 7% | 9.00 |
| declaration + definition (1000 methods/owner) | 1.41 µs | 16% | 14.01 | 884.8 ns | 6% | 14.01 |
| declaration + definition (5000 methods/owner) | 1.50 µs | 16% | 14.00 | 875.2 ns | 16% | 14.00 |
| redefinition of annotated methods, unannotated | 269.5 ns | 3% | 2.00 | 223.4 ns | 540% | 2.00 |
| reflection: own_annotations_for | 134.4 ns | 2% | 0.00 | 75.1 ns | 16% | 0.00 |
| reflection: annotations_for (defined once) | 202.7 ns | 13% | 1.00 | 106.2 ns | 14% | 1.00 |
| reflection: annotations_for (unannotated override) | 179.4 ns | 7% | 1.00 | 93.4 ns | 5% | 1.00 |
| reflection: annotation(name, type) | 262.0 ns | 14% | 1.00 | 110.7 ns | 12% | 1.00 |
| reflection: annotated_with (100 methods) | 27.46 µs | 3% | 106.00 | 13.07 µs | 15% | 106.00 |
| call: plain method | 14.7 ns | 6% | 0.00 | 14.2 ns | 8% | 0.00 |
| call: annotated method | 14.8 ns | 7% | 0.00 | 14.0 ns | 202% | 0.00 |

### Retained memory

| phase (growth since the previous phase) | KB, YJIT off | live slots | KB, YJIT on | live slots |
|---|---:|---:|---:|---:|
| require | 33.7 | 835 | 33.7 | 835 |
| 200 classes x 50 annotated methods | 3116.3 | 72304 | 3116.3 | 72235 |
| annotations_for on every method | 0.4 | 815 | 0.4 | 807 |
| annotated_with on every class | 0.2 | 1021 | 1.9 | 1008 |
| global Adornment.annotated_with | 2.9 | 215 | 362.2 | 410 |

## Method

- Each case warms up, then runs a fixed number of operations with GC enabled. Batch operations
  (1,000 or 5,000 definitions) run `GC.start` before each operation. Times are per unit (one
  definition, one call, ...). Objects are `GC.stat(:total_allocated_objects)` deltas per unit,
  which count objects, not bytes.
- Medians over the processes are reported. "Spread" is (max − min) / median. Some cases have
  outliers (a single slow process); medians are robust to them, but small differences (under
  about 10%) are within noise on this machine.
- `require` is measured inside the process, around `require` alone, so VM boot is excluded.
- "declaration + definition" builds a fresh activated class and, per method, declares
  `Traced(span: "s")` and then calls `define_method`. "Unannotated" definitions use
  `define_method` on an activated class, which is the cost every non-annotated method of an
  activated class pays.
- "annotations_for (unannotated override)" reads a subclass override without annotations:
  reflection is strict, so the answer is empty.
- The "signatures" rows measured the Prism signature reader, removed with the keyword-default
  declarations (2026-10-18). Core has no parameter reading any more (adornment-api reads its
  `Params` by reflection), so `benchmarks/suite.rb` has no replacement rows.
- Retained memory: after four full GCs, the growth of live heap slots and of
  `ObjectSpace.memsize_of_all` per phase (bytes CRuby attributes to live objects, including Hash
  and Array buffers; not RSS, no JIT code or malloc fragmentation). The workload is 200 activated
  classes with 50 annotated methods each, then reflection over all of them. The global
  `annotated_with` phase under YJIT retains about 360 KB; that is not annotation data (probably
  YJIT bookkeeping) and was not investigated.

## History

### Module functions instead of `class << self` (2026-10-21)

Reflection under YJIT measured 1.07–1.13x the baseline in `compare.rb`. A focused A/B (Ruby 4.0.5,
YJIT on, the baseline's lib at commit cfbf764 against the current lib, 16 alternating processes
each) put the real difference at 2–6% (`annotations_for` on an unannotated override 107.9 vs
102.1 ns, ranges not overlapping), the rest being noise. The cause: `Query`'s functions had moved
from `module_function` into `class << self`, where constant reads (`State`, `NONE`) get inline
caches YJIT cannot inline. With `module_function` back in `Query`, `Pending`, `Attachment`,
`Immutable` (and `def self.` for the `Core` helpers) the same A/B measured 0.99x the baseline
code on every reflection case. Without YJIT nothing changed. A full `compare.rb` run afterwards
(against the 2026-10-18 baseline, recorded at another time): reflection under YJIT 1.02–1.07x
(spreads 8–9%), everything else as before; `require` allocates 20 more objects (1807 → 1827),
the private instance copies `module_function` defines.

### Baseline recorded 2026-10-18

| | |
|---|---|
| Ruby | 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [arm64-darwin25], Prism 1.9.0 |
| Machine | Apple M5, 10 CPUs, macOS (Darwin 25.4.0 arm64); a developer laptop, not isolated from other work |
| Samples | 7 processes per JIT mode (memory: 5) |
| Identity | the JSON records SHA-256 of `suite.rb` and of this gem's `lib/` |
| Code | after visibility changes became definitions (see [History](#visibility-changes-as-definitions-2026-10-18)) |

Only this machine and Ruby version were benchmarked. The Docker runs on 3.3 and 3.4 were
correctness runs, not benchmarks.

| case | YJIT off | spread | objects | YJIT on | spread | objects |
|---|---:|---:|---:|---:|---:|---:|
| require | 2.21 ms | 16% | 2429.00 | 2.17 ms | 5% | 2429.00 |
| reflection: Adornment.annotated_with (global, 4 owners) | 18.31 µs | 3% | 107.00 | 10.28 µs | 4% | 107.00 |
| activation (class + include Adornment[...]) | 10.15 µs | 5% | 84.00 | 61.54 µs | 2% | 83.00 |
| definition: plain class (baseline) | 188.6 ns | 8% | 2.00 | 195.4 ns | 4% | 2.00 |
| definition: activated, unannotated | 271.4 ns | 5% | 2.00 | 225.0 ns | 2% | 2.00 |
| definition: activated subclass, unannotated | 270.3 ns | 5% | 2.01 | 227.5 ns | 3% | 2.01 |
| declaration (repeatable, queued) | 741.1 ns | 7% | 13.01 | 551.1 ns | 4% | 13.01 |
| declaration + definition (1000 methods/owner) | 1.63 µs | 2% | 18.01 | 1.07 µs | 1% | 18.01 |
| declaration + definition (5000 methods/owner) | 1.81 µs | 2% | 18.00 | 1.18 µs | 6% | 18.00 |
| redefinition of annotated methods, unannotated | 268.2 ns | 3% | 2.00 | 222.6 ns | 3% | 2.00 |
| Adornment.attach | 702.5 ns | 2% | 3.00 | 382.8 ns | 3% | 3.00 |
| reflection: own_annotations_for | 135.0 ns | 2% | 0.00 | 81.7 ns | 2% | 0.00 |
| reflection: annotations_for (defined once) | 201.5 ns | 10% | 1.00 | 107.9 ns | 3% | 1.00 |
| reflection: annotations_for (unannotated override) | 180.2 ns | 8% | 1.00 | 93.1 ns | 6% | 1.00 |
| reflection: annotation(name, type) | 268.7 ns | 9% | 1.00 | 109.2 ns | 5% | 1.00 |
| reflection: annotated_with (100 methods) | 30.19 µs | 1% | 106.00 | 13.70 µs | 4% | 106.00 |
| signatures: 1 method, one-off read (removed, see below) | 179.89 µs | 4% | 1259.05 | 332.19 µs | 22% | 1259.01 |
| signatures: 20 methods, one read (removed) | 25.62 µs | 34% | 255.40 | 19.08 µs | 7% | 255.40 |
| signatures: 20 methods, 20 reads (removed) | 28.33 µs | 39% | 264.95 | 21.31 µs | 79% | 264.95 |
| call: plain method | 14.7 ns | 16% | 0.00 | 14.2 ns | 4% | 0.00 |
| call: annotated method | 14.6 ns | 8% | 0.00 | 13.9 ns | 2% | 0.00 |

Retained memory:

| phase (growth since the previous phase) | KB, YJIT off | live slots | KB, YJIT on | live slots |
|---|---:|---:|---:|---:|
| require | 46.6 | 1177 | 46.6 | 1177 |
| 200 classes x 50 annotated methods | 3116.1 | 73155 | 3116.1 | 73051 |
| annotations_for on every method | 0.6 | 812 | 0.6 | 809 |
| annotated_with on every class | 0.2 | 1019 | 1.9 | 1007 |
| global Adornment.annotated_with | 2.5 | 212 | 361.8 | 407 |

After removing keyword-default parameter declarations:

`ruby benchmarks/compare.rb` and `memory_compare.rb` were re-run (7 samples, YJIT off and on, run
on a scratch copy so `results/` keeps the recorded run) after the signature reader was removed and
`Params` moved to adornment-api. Against the baseline above: every case within 0.84–1.05 of it
(declarations 8–16% faster with 2 fewer objects, `require` 2–3% slower with 173 fewer objects,
reflection and calls unchanged within their spread). Retained memory after `require` dropped from
46.6 to 43.2 KB; the other memory phases are unchanged. The "signatures" rows no longer exist.

### Plain-class types and attachment-time validation (2026-10-19)

`ruby benchmarks/compare.rb` and `benchmarks/memory_compare.rb` on a scratch copy (Ruby 4.0.5,
7 samples / 5 processes, against the 2026-10-18 baseline; not re-recorded). Types are plain
classes with an ordinary `initialize`: declaration methods call `Type.new` directly, with no
binder or signature reading.

| case | YJIT off | YJIT on | objects (baseline → now) |
|---|---:|---:|---:|
| require | 0.91x | 0.93x | 2429 → 2091 |
| activation (class + include Adornment[...]) | 0.94x | 0.98x | 84 → 81 |
| declaration (repeatable, queued) | 0.78x | 0.66x | 13 → 9 |
| declaration + definition (1000 methods/owner) | 0.96x | 0.92x | 18 → 16 |
| declaration + definition (5000 methods/owner) | 0.91x | 0.92x | 18 → 16 |
| reflection: `annotation(name, type)` | 0.97x | 1.11x | 1 → 1 |
| reflection: `annotations_for` (unannotated override) | 0.97x | 1.14x | 1 → 1 |
| reflection: `annotated_with` (100 methods) | 0.95x | 1.08x | 106 → 106 |
| definition: plain class (control) | 0.98x | 0.99x | 2 → 2 |
| call: plain / annotated method | 0.99x / 1.00x | 0.97x / 1.00x | 0 → 0 |

Measured after `Adornment.attach` was removed and the two kinds were split
(`Adornment::Annotation[...]` / `Adornment::ParameterAnnotation[]`, no `target` policy, policy
cache without a generation check). The other cases are within 0.92–1.04x. Under YJIT the
reflection rows stay 8–14% above the baseline (spreads 4–7%); `annotations_for` on an
unannotated override reads no policy at all, so that part is not the policy lookup. Before the
split `annotation(name, type)` measured 1.21x / 1.23x: it read the merged policy twice, each
time through the generation check (about 40 ns per read without YJIT).

Retained memory for 200 classes x 50 annotated methods: 3116.4 KB (baseline 3116.1 KB), both
YJIT modes; plain instances with instance variables cost what `Data` instances did.

An intermediate version (named `Data` types with a binder that read the initializer's signature
on every `build`) measured 1.7x on declaration + definition. A stage breakdown against HEAD
showed where it went: the signature read (`instance_method(:initialize)`, `super_method`s and
`parameters`) was about half of every construction, and the old factories' all-keywords fast
path was gone. Plain classes remove both. What remains is attachment-time validation: one
`Adornment::Site` and a `validate` call per annotation (about +190 ns per annotated definition,
measured against HEAD).
`Adornment.attach` (measured at 1.56x / 1.58x before its removal, from validating the whole set
and capturing the caller location) was then removed, and its row with it.

### Visibility changes as definitions (2026-10-18)

A visibility change of an inherited method (`private :x`, `private_class_method :x`) became an
override like any other: it takes pending declarations and has its own annotations. The
classifier is gone: definitions no longer check whether an entry is visibility-only, `attach`
no longer rejects such entries, and the resolved lookup reads the method's owner with no
fallback walk. Before is the previous baseline (recorded the same day); after is the current one.

| case | YJIT off: before → after | YJIT on: before → after | objects |
|---|---:|---:|---:|
| reflection: annotations_for (unannotated override) | 421.3 ns → 180.2 ns (-57%) | 221.9 ns → 93.1 ns (-58%) | 3 → 1 |
| Adornment.attach | 1.28 µs → 702.5 ns (-45%) | 693.6 ns → 382.8 ns (-45%) | 5 → 3 |
| declaration + definition (1000 methods/owner) | 2.33 µs → 1.63 µs (-30%) | 1.51 µs → 1.07 µs (-29%) | 20 → 18 |
| declaration + definition (5000 methods/owner) | 2.51 µs → 1.81 µs (-28%) | 1.56 µs → 1.18 µs (-24%) | 20 → 18 |

- An unannotated method now costs the same as an annotated one: one UnboundMethod, no ancestors.
- A definition with declarations pending and `attach` no longer build the ancestors Array to
  compare against the next definition.
- `require` allocates 70 fewer objects (one file less); every other case moved within noise,
  and retained memory is unchanged.

### Reflection through the method's owner (2026-10-18)

Strict queries (`annotations_for`, `annotation`, `annotated_with`) ask Ruby which module's method
runs (`instance_method(name).owner`) and read that module's entry; the ancestors are walked only
when that module holds no annotations (it may be a visibility-only entry). `module_function`
copies became definitions, and the walk and its visibility check were shared. Before is the
previous baseline (recorded the same day); after is the current one.

| case | YJIT off: before → after | YJIT on: before → after | objects |
|---|---:|---:|---:|
| reflection: annotations_for (defined once) | 723.4 ns → 200.9 ns (-72%) | 356.7 ns → 105.5 ns (-70%) | 2 → 1 |
| reflection: annotations_for (unannotated override) | 542.4 ns → 421.3 ns (-22%) | 285.7 ns → 221.9 ns (-22%) | 4 → 3 |
| reflection: annotation(name, type) | 792.0 ns → 267.7 ns (-66%) | 346.7 ns → 108.7 ns (-69%) | 2 → 1 |
| reflection: annotated_with (100 methods) | 82.81 µs → 29.87 µs (-64%) | 36.23 µs → 14.03 µs (-61%) | 212 → 106 |

- A resolved lookup costs one UnboundMethod instead of the ancestors Array plus a holder/side
  pair: about 3× faster, half the allocations.
- An unannotated override reuses the method it already looked up for the visibility check, so it
  is faster too (it used to compare two freshly looked-up methods).
- Every other case moved within noise (±3%); `require` allocates 15 fewer objects.

### Hook simplification and aliases (2026-10-18)

The definition hooks were reduced to `method_added`, `singleton_method_added` and `const_added`,
acting only when the owner has pending declarations: no per-event frame stack, no removal hooks,
hooks prepended once per ancestry. Aliases take declarations like any definition. Before is the
`Data`-based core with the old dispatch, measured the same day with the same suite and sample
count (the legacy implementation, measured in both runs, moved by 1–2%).

| case | YJIT off: before → after | YJIT on: before → after |
|---|---:|---:|
| definition: activated, unannotated | 494.9 → 267.7 ns (−46%) | 341.7 → 224.2 ns (−34%) |
| definition: activated subclass, unannotated | 623.3 → 267.4 ns (−57%) | 367.1 → 226.1 ns (−38%) |
| redefinition of annotated methods, unannotated | 1.36 µs → 270.6 ns (−80%) | 710.4 → 224.9 ns (−68%) |
| declaration + definition (1000 methods/owner) | 2.67 → 2.33 µs (−13%) | 1.64 → 1.51 µs (−8%) |
| declaration + definition (5000 methods/owner) | 2.81 → 2.46 µs (−12%) | 1.72 → 1.60 µs (−7%) |
| reflection: own_annotations_for | 104.5 → 134.4 ns (+29%) | 64.9 → 82.4 ns (+27%) |
| reflection: Adornment.annotated_with (global, 4 owners) | 15.06 → 18.15 µs (+21%) | 8.88 → 10.41 µs (+17%) |

- Ordinary definitions cost half as much, subclasses most, since they no longer pass through a
  second copy of the hooks. An unannotated redefinition no longer clears anything (2 objects
  instead of 4).
- `own_annotations_for` and the global `annotated_with` now check that the owner still defines
  the method, which replaced the removal hooks.
- Everything else, including calls to annotated methods, moved within noise; `require`
  allocates 163 fewer objects. Retained memory is unchanged (3116.2 KB for 10,000 annotations).

### Legacy vs adornment-core (2026-10-17)

The rewrite measured against the legacy implementation (`../lib`, since deleted) in alternating
processes. The full tables are in git history (`benchmarks/results/` before 2026-10-18).

Execution:

- **Calls to annotated methods cost the same as calls to plain methods**, with 0 allocations, in
  both implementations and both JIT modes. The specs also check this directly: method identity,
  zero extra allocations per call, and no Adornment code running during calls.

Boot and compilation work, where the rewrite changed things:

- Unannotated definitions on activated owners are 10–29% faster and allocate exactly what a plain
  class allocates: 2 objects, against 3–4 in legacy.
- Annotated definitions (declaration + definition) are 2.9–5.5× faster. Legacy slows down as an
  owner grows (7.8 → 11.0 µs per method from 1,000 to 5,000 methods, interpreter), from the
  copy-on-write entry hash. adornment-core stays flat (2.68 → 2.86 µs).
- Unannotated redefinition of annotated methods is 4–7× faster.
- Reflection: `annotations_for` on a method defined once is about 11× (interpreter) and 19×
  (YJIT) faster, with 2 allocations instead of 25. `annotated_with` on a 100-method class is
  11–26× faster.
- Signature reading (before its removal): one read of one method was 13–20% faster than legacy,
  one read of 20 methods on par.

Unchanged or slower:

- `require` is 7–9% slower: 2.33 → 2.50 ms in the interpreter and 2.29 → 2.50 ms with YJIT.
  adornment-core allocates 52 more objects at require. The type system and owner API are larger;
  the lint is autoloaded (inspection and placement diagnostics, autoloaded at the time, have
  since been removed; require time was not re-measured after that). (Before the tracer removal it
  was 11–25% slower, with 156 more objects.)
- `Adornment.attach` is on par in the interpreter (+5%, within spread) and 29% faster under YJIT.
  It now also rejects visibility-only entries, which costs one ancestry check.
- Activation, `own_annotations_for` and global `Adornment.annotated_with` are on par (within 7%).
- Under YJIT, activation takes about 62 µs in both implementations (11 µs without YJIT). This
  was not investigated; it comes from creating classes and including modules under YJIT, not from
  code that differs between the two.

These are microbenchmarks on one machine. They show where time goes and that the rewrite did not
regress the measured paths except `require`; they are not application-level speedups.

Retained memory, legacy vs adornment-core:

- Defining the annotated classes retains 0.8% less in adornment-core (−26.5 KB for 10,000
  annotated methods). Before the tracer was removed it retained 0.8% more (+24.5 KB): each
  owner's `State` held a per-fiber pending Hash, which is now one fiber-local table.
- A first draft kept a frozen snapshot next to the live Hash after `annotated_with`, which
  retained +356 KB in this workload. This measurement found it. Now a whole-side read freezes the
  live Hash in place and the next write copies it, so only one Hash per side exists at rest
  (`state_snapshot_spec.rb`).
- The global `annotated_with` phase under YJIT retains about 360 KB in both implementations. That
  is not annotation data; it is probably YJIT bookkeeping and was not investigated.

### Tracer removal (2026-10-17)

The TracePoint definition window (`:class`/`:end`/`:raise`) was replaced by a fiber-local table
of pending declarations keyed by the owner's `object_id`. The table below compares adornment-core
with itself: the previous recorded run (same machine, Ruby, suite and sample count) against this
one. The legacy column is the same legacy code measured in both runs, so its change is this
machine's drift between the runs (here 0–6% faster across the board).

| case | interpreter before → after | YJIT before → after | legacy drift (interp / YJIT) |
|---|---:|---:|---:|
| require | 2.95 → 2.50 ms (−15%) | 2.60 → 2.50 ms (−4%) | −1% / −2% |
| declaration (repeatable, queued) | 859 → 783 ns (−9%) | 619 → 558 ns (−10%) | −1% / −4% |
| declaration + definition (1000 methods/owner) | 3.06 → 2.68 µs (−12%) | 1.94 → 1.64 µs (−16%) | −3% / −6% |
| declaration + definition (5000 methods/owner) | 3.22 → 2.86 µs (−11%) | 2.10 → 1.71 µs (−19%) | −3% / −4% |
| redefinition of annotated methods, unannotated | 1.51 → 1.36 µs (−11%) | 807 → 711 ns (−12%) | −4% / −2% |
| definition: activated, unannotated | 475 → 495 ns (+4%) | 349 → 340 ns (−3%) | −2% / −1% |
| call: annotated method | 15.0 → 14.6 ns | 14.3 → 13.8 ns | −1% / −2% |

- Declaring is 9–19% faster: no TracePoint to enable and disable, and no lock around the queue.
- `require` loads less (no `window.rb`, no isolation thread code): 104 fewer objects.
- One more object per declaration + definition (19 → 20): the per-owner `Pending::Queue`.
- Unannotated definitions on activated owners: +4% in the interpreter, −3% with YJIT. Both are
  within spread (4% and 1%); the fast path now checks the fiber-local table instead of the
  owner's per-fiber Hash.
- Every other case moved by no more than the legacy drift.
- With no TracePoint, the YJIT invalidation the README used to list as a limitation (once per
  process, at the first declaration) no longer happens. That was not measured here.

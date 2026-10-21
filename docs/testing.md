# Testing

Run these commands from `adornment-core/`:

```sh
bundle install
bundle exec rspec
RUBYOPT=--yjit bundle exec rspec
```

The last command repeats the suite with Ruby's optional just-in-time compiler enabled.
To run every package together, use `bundle exec rake` from the repository root after
installing each package's dependencies; see [Development](../../README.md#development).

The suite checks attachment, reflection, inheritance, immutability, and the guarantee
that annotations do not wrap method calls. README code blocks are not executed by this suite.

## Latest local check: 2026-10-21

The repository-wide `bundle exec rake` run passed on CRuby 4.0.5, arm64-darwin25,
with YJIT off. This package passed **222 examples, 0 failures**. Across the repository,
the umbrella, core, DTO, and API suites passed 3, 222, 95, and 326 examples respectively.

This documentation check did not rerun YJIT, Rack 2, Docker, signature validation,
negative controls, installed-gem checks, or benchmarks. The dated records below describe
earlier checks and must not be read as new results for the current working tree.

A negative control deliberately breaks a mechanism in a scratch copy and checks that
the tests detect it. A snapshot compares generated output with a saved expected result.

[Documentation index](../../docs/README.md)

## Earlier verification records

Recorded for the version 0.1.0 checkout on 2026-10-21; this is a test record, not a release announcement.

### Suite

`bundle exec rspec` runs 224 examples. The suite loads only this gem's `lib/`;
`consumer_spec.rb` and `platform_spec.rb` run child processes with `-I lib` only. README code
blocks are not run by the suite.

The behavioral requirements come from the legacy implementation's suite (222 examples, ported
file by file; the legacy code has since been deleted). The specs added since cover what core does
differently or newly:

- `types_spec.rb`, `type_construction_spec.rb`: named plain-class types, Ruby's own construction
  and argument errors, policy validation, inherited policy merging and its cache (frozen types
  included), bare inclusion, unsupported hosts, value equality, hash and pattern matching.
- `validation_spec.rb`: `validate(site)` on every definition that takes declarations, the
  complete proposed set, declaration locations, `DefinitionError` causes, nothing attached or left
  pending on failure.
- `extension_metadata_spec.rb`: an extension's own metadata objects held by a method annotation,
  the freezing rule on them, rejection in method contexts, no Prism at require.
- `pending_spec.rb`: the fiber-local pending table, cross-owner and `const_added` leftovers.
- `dispatch_fast_path_spec.rb`, `execution_contract_spec.rb`: no wrappers, no per-call
  allocations or Adornment calls, an allocation-free idle definition path.
- `lifecycle_spec.rb` (release of owners, unregister, reload), `state_snapshot_spec.rb` (one Hash
  per side at rest), `alias_spec.rb`, `module_function_spec.rb`, `definitions_extra_spec.rb`,
  `consumer_spec.rb` (an extension built on the public API only).

### Ruby versions actually run

| Ruby | YJIT | Where | Result |
|---|---|---|---|
| ruby 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [arm64-darwin25] | off | local (macOS) | 224 examples, 0 failures |
| same | on (`RUBYOPT=--yjit`) | local | 224 examples, 0 failures |
| ruby 3.4.11 (2026-09-23 revision 592f1ffdb3) +PRISM [aarch64-linux] | off | Docker `ruby:3.4-slim` | 224 examples, 0 failures |
| ruby 3.4.11 +YJIT +PRISM [aarch64-linux] | on | Docker `ruby:3.4-slim` | 224 examples, 0 failures |
| ruby 3.3.12 (2026-07-16 revision 0581089df9) [aarch64-linux] | off | Docker `ruby:3.3-slim` | 224 examples, 0 failures |
| ruby 3.3.12 +YJIT [aarch64-linux] | on | Docker `ruby:3.3-slim` | 224 examples, 0 failures |

```bash
bundle exec rspec
RUBYOPT=--yjit bundle exec rspec
```

The gemspec declares `required_ruby_version >= 3.3`. Versions not in the table (3.3.0–3.3.11,
3.4.0–3.4.10, 4.0.0–4.0.4, x86_64, Linux outside Docker, Windows) were not run.

## CI

`.github/workflows/ci.yml` (repository root) runs the suite on Ruby 3.3, 3.4 and 4.0, with YJIT on
3.4 and 4.0. On 4.0 without YJIT it also runs RuboCop (`BUNDLE_WITH=tooling`) and checks the
installed gem: it builds and installs it, loads it with no Bundler, `-I` or `RUBYLIB`, checks that
every loaded file comes from the installation, and declares, reflects and verifies (lint included)
one annotation.

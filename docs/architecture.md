# adornment-core architecture

This guide is for contributors and authors of extensions. It explains how an annotation
gets attached to a method and how an extension reads it back. For usage examples, start
with the [core guide](../README.md); for other topics, see the
[documentation index](../../docs/README.md).

The central rule is simple: annotations describe methods; they do not wrap or execute
them. An extension reads that description and decides what to do with it.

## Boundaries

Core is a metadata engine. It defines annotation types, attaches immutable values to methods,
resolves them along Ruby's method lookup, and reports leftovers and mistakes. It has no parameter
declaration or resolution mechanism of its own. It never changes how a method runs.

Extension gems interpret the metadata. They discover owners, read annotations (and `Method#parameters`) once,
validate their own rules, and compile plans that run without calling Adornment. HTTP, operation
execution, persistence, coercion and type checking live in those gems.

## Layout

```text
lib/adornment/core.rb                    public facade: every Adornment.* method, requires, autoloads
lib/adornment/core/
  version.rb, errors.rb                  VERSION and the errors (Adornment::Error and subclasses)
  annotation.rb                          Adornment::Annotation (instance module with the value behavior,
                                         Annotation[...]), Core::PolicyModule, Policies, TypeMethods
  base.rb                                Core::Base (what Adornment[...] returns), Core::Target (activation, declaring)
  reflection.rb                          Core::Reflection (reading), the Core::Declaration record
  hooks.rb                               Core::Hooks (method_added, singleton_method_added, const_added),
                                         Core::Propagation (included, prepended, extended)
  immutable.rb                           the freezing rule (Adornment.immutable_copy)
  private/                               internals
    utils.rb                             Utils: check_type!, declaration_name, render_arguments
    annotation_methods.rb                per-owner AnnotationMethods module (the Traced(...) methods)
    pending.rb                           fiber-local pending declarations keyed by owner (PendingDeclaration)
    state.rb                             per-owner State, weak Registry
    site.rb                              Core::Site, the argument of Annotation#validate
    attachment.rb                        writes: grant, declare, added, validate!, verify
    query.rb                             reads: Query (the lookups behind Reflection)
  diagnostics/                           diagnostics (autoloaded)
    lint.rb                              Core::Lint, the bare-constant lint (its own lazy Prism loader)
```

Namespaces: what users write (`Adornment[...]`, `Adornment::Annotation`, the errors) lives
directly under `Adornment`; everything else, public owner API and records included, lives under
`Adornment::Core`.

Dependencies point one way. The facade and the owner API use the internals (attachment for
writes, query for reads), which use the types. State depends on nothing above it, and only the
lint loads Prism.

## Types

There is one kind: a user's plain class that includes what `Adornment::Annotation[...]` returns,
a `PolicyModule` (a dedicated `Module` subclass, so policy modules are told apart from any other
ancestor) holding only the policies it was given (`repeatable:`, `targets:`), frozen. It includes
the marker `Adornment::Annotation`, whose `append_features` rejects every includer except a
`PolicyModule`, so a bare `include` raises and `type < Annotation` means "an annotation type".
Method contexts (`check_type!`, `check_instance!`) need only that `<` or `is_a?`.
Per-parameter metadata is not core's: extensions keep their own value objects (see
[Per-parameter metadata](#per-parameter-metadata)).

- **Inclusion.** `append_features` checks the host (a class, not a `Data` or `Struct`), then
  includes and extends `TypeMethods`. Ruby skips modules a superclass already has, so
  a subclass's own policy module adds no second copy.
- **Policies.** `Policies.of(type)` merges the policy modules in the type's ancestors, least
  specific first (values replace, arrays included), then the defaults, and caches the result in
  the type (`@__adornment_policy__`). Policies change only when a policy module is included, so
  the inclusion drops the cache of the host and, through `Class#subclasses`, of every subclass;
  reads are one instance variable and a Hash lookup, with no generation check. A frozen type
  cannot hold the cache, so its policy is merged on every read.
- **Construction.** There is no binder and no signature reading: declaration methods call
  `Type.new(*args, **kwargs)`, so Ruby's own initializer decides positional,
  keyword, required and default arguments, and raises its own `ArgumentError`s.
  `TypeMethods#new` calls `super` and then `Policies.seal`: every instance variable is copied and
  deep-frozen, then the instance is frozen. An instance the
  initializer froze itself is left as it is.
- **Value behavior.** Fields are the instance variables. `Adornment::Annotation` defines `==`,
  `eql?`, `hash` (class plus `to_h`, which is order-independent), `to_h`, `deconstruct_keys` and
  `inspect` over them, without enumerators. `Type[...]` raises `TargetError` (the call form is
  the only way to declare).

## Declaration lifecycle

1. **Declare.** `Traced(span: "x")` is a singleton method from the owner's `AnnotationMethods` module.
   It captures `caller_locations(1, 1).first` (the user's line, once), builds the annotation with
   `Type.new`, and calls `Attachment.declare`, the shared enqueue that `adorn` also uses with
   its own captured location. That checks the instance (an `Annotation`, not a type or any other
   object) and queues a `PendingDeclaration`
   in the fiber-local `Pending` table under the owner. If another owner already has
   pending declarations there, it raises `LeftoverAnnotations` for them and clears the table.
2. **Define.** Ruby calls `method_added` (or `singleton_method_added`) on the owner's singleton
   class. `Hooks` checks the fiber-local pending table for the owner; with nothing pending it
   only calls `super`, so ordinary definitions allocate nothing.
3. **Attach.** With declarations pending, every entry Ruby reports is a definition: `def`,
   copies (aliases, `module_function`) and visibility changes of inherited methods alike, since
   Ruby makes each of them an own entry of the owner. `Attachment.added` takes the owner's
   queue (so a failure leaves nothing pending), checks `targets`, runs each annotation's
   `validate(site)` with one `Site` for the whole definition (the complete frozen set; no lock
   held),
   and only then replaces the method's entry with the frozen Array. A validator's StandardError
   becomes `DefinitionError` (its `cause`), its message prefixed with `Owner#name` and its
   backtrace starting at the declaration. Declarations are the only way to attach. Nothing else
   is tracked:
   unannotated redefinitions and removals leave the entry; reflection only reads owners that
   still define the method. A repeated delivery of the same event (hooks twice in an ancestry,
   when a superclass is activated after its subclass) finds nothing pending and does nothing.
4. **Leftovers.** Nothing is traced. Leftovers raise `LeftoverAnnotations` on a declaration for
   another owner, on `const_added` of the owner (`Hooks#const_added`), or in
   `verify_adornments!` / `verify_all!`. A body end reports nothing, so it never masks an
   exception unwinding the body.
5. **Reflect.** Strict queries (`annotations_for`, `annotation`, `annotated_with`) ask Ruby which
   module's method runs (`instance_method(name).owner`) and return that module's entry itself (no
   copy), with no ancestor walk. `Query.each_entry` walks the ancestors and yields each own
   entry, nearest first, stopping at an undef barrier; `find_annotation` and `declarations_for`
   use it.

## What was taken from sorbet-runtime, and what was not

Reference: sorbet-runtime 0.6.13517 (`lib/types/sig.rb`, `lib/types/private/decl_state.rb`,
`lib/types/private/methods/_methods.rb`, `lib/types/private/caller_utils.rb`). Sorbet solves a
related problem: `sig { ... }` before `def` must bind to the next method. Its machinery is built
for type checking and method wrapping. No Sorbet code was copied and no `T::Private` API is used,
only techniques.

| Sorbet technique | Here | Why |
|---|---|---|
| `sig` captures `Kernel.caller_locations(1, 1)&.first`: one frame, no stack scan, kept as a `Location` and released once used | declaration methods and `adorn` capture one frame; `PendingDeclaration#location` formats `path:line` only when read | no string per declaration; diagnostics keep the exact line |
| `_on_method_added` consumes the thread-local `DeclState` and returns early when nothing is declared | `Hooks#method_added` checks the fiber-local pending table and returns when nothing is pending | definitions cost one lookup |
| `last_method_key` guards against repeated hook copies dropping a sig | not needed: nothing is dropped, so a repeated delivery finds nothing pending and does nothing; hooks are prepended once per ancestry | Sorbet drops a sig on an unannotated redefinition; core keeps annotations |
| declaration state separate from the method registry (`DeclState` vs `Methods`) | `Pending` (fiber-local queues) and `State` (entries per owner) separate from `Attachment` (rules) | the lifecycle is readable on its own |
| a second `sig` before a `def` raises and resets the declaration | a non-repeatable type declared twice raises `DuplicateAnnotation` and clears the queue | same failure mode, same recovery |
| heavy work deferred (sig blocks run on first call or `run_all_sig_blocks`) | definitions only attach; Prism runs only in the lint | definitions stay cheap |

Not taken, because it is machinery for type checking and wrapping, or contradicts core's
contract:

- **Method wrappers and first-call replacement** (`replace_method`, `CallValidation`). Core must
  not change method execution.
- **One thread-global active declaration.** Core keeps one fiber-local table keyed by the owner
  (compared by identity): leftovers are attributed to an owner, and fibers do not take each
  other's declarations.
- **Global registries keyed by `"#{owner.object_id}##{name}"` strings.** State lives in the owner,
  so it dies with it, and the registry of owners is weak.
- **`T::Configuration` error handlers.** Core raises.
- **final/abstract/sealed checks and viral hook installation on `Module`/`Class`.** Hooks go only
  on activated owners.

## Data structures and invalidation rules

| Structure | Lives in | Lifetime / invalidation |
|---|---|---|
| `State` | hidden ivar of the owner | with the owner |
| entries (`{name => frozen Array}`, per side) | `State`, one Hash per side, written under the lock | replaced per name; reads of one entry are lock-free (GVL-atomic `Hash#[]`, Symbol keys) |
| side snapshot | the same Hash, frozen in place by the first whole-side read | **the next write copies it** into a new mutable Hash; a held snapshot never changes; one Hash per side at rest |
| pending table (`{owner => [PendingDeclaration]}`, by identity, at most one entry) | fiber-local | until consumed, verified, or reported by another owner's declaration or `const_added` |
| owner registry | `ObjectSpace::WeakMap` | weak; `unregister` removes, re-activation adds |
| `AnnotationMethods` types | per-owner module | grows with `use_annotations` |

There is no process-global cache of reflection results or parse trees. Ancestry changes, undef,
visibility changes and reloads can all invalidate a lookup, and no single counter tracks them all.

## Per-parameter metadata

Core has no parameter annotations. An extension that needs per-parameter metadata holds its own
ordinary value objects in a method annotation of its own and checks them against
`Method#parameters` itself; core attaches them nowhere, never reads signatures or their
defaults, and applies only the freezing rule to the annotation's fields (containers copied,
other objects kept). adornment-api's `Params` does so with public API only: a named annotation
class with a keyword-mapping initializer whose values are adornment-api's own markers.
Its `validate(site)` method checks the mapping against `site.method.parameters` when core
attaches the annotation. The API compiler checks the signature again when building an app,
including methods without `Params`. adornment-api installs no definition hooks of its own.

## Module functions on hot paths

`Query`, `Pending`, `Attachment` and `Immutable` define their functions in the module body with
`extend self`, and `Utils` with `def self.`, not inside `class << self`. A constant read in a
method defined in `class << self` gets an inline cache tied to that lexical scope, which YJIT
checks with a call on every read instead of inlining the constant. On the reflection path (`State`, `NONE`)
that cost 2–6% per query under YJIT (see docs/benchmarks.md, 2026-10-21).

## Concurrency assumptions

- CRuby's GVL makes `Hash#[]`/`Hash#[]=` with Symbol keys atomic with respect to other Ruby
  threads. Lock-free entry reads rely on this, as the legacy implementation did.
- Locks are short and never held while user code runs (callbacks, `inspect` of user values).
- Concurrent definition on one owner is unsupported. It neither loses nor corrupts registrations
  (`concurrency_spec.rb`), but the ordering is unspecified.

## Extension contract

Extensions use only the public API (README, "Public API"): they define annotation types as
classes, export an opt-in module (activation plus constants for their own metadata objects),
discover owners explicitly or through `Adornment.annotated_with`, read their declarations with
the reflection API and `Method#parameters`, compile plans, and run them without calling
Adornment. `examples/events/` does exactly this (the extension in `events.rb`, an application
in `app.rb`), and `consumer_spec.rb` checks that it uses no internals, that a handler with the
wrong signature is rejected when it is defined, and that publishing an event calls no Adornment
code.

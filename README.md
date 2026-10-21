# adornment-core

The declarative metadata engine behind Adornment: annotation types, declarations above `def`,
attachment, reflection along Ruby's method resolution, verification and diagnostics.

```ruby
require "adornment/core"

class Traced
  include Adornment::Annotation[]

  attr_reader :span

  def initialize(span: nil)
    @span = span
  end
end

class Orders
  include Adornment[Traced]

  Traced(span: "orders.fetch")
  def fetch(id) = id
end

Orders.annotations_for(:fetch) # => [#<Traced span="orders.fetch">]
```

- Annotations are frozen values you reflect on. **Core never changes how a method runs**: no
  wrappers, no method replacement, nothing prepended to the owner. A call to an annotated method
  executes no Adornment code and allocates nothing extra.
- Pure Ruby, no runtime dependencies. Prism (a default gem since Ruby 3.3) is loaded only to run
  the lint. Declarations never read source files.
- CRuby only, Ruby >= 3.3 (see [Ruby versions](#ruby-versions) for what was actually tested).
- Version 0.1.0, the first release.

Core owns annotation types, declarations, attachment, reflection, verification and diagnostics.
HTTP, operation execution, persistence, coercion and runtime type checking belong to the gems
built on it (`adornment-api`, `adornment-operation`, `adornment-repo`, ...).

### Gem names

| gem | require | role |
|---|---|---|
| `adornment-core` (this gem) | `require "adornment/core"` | the engine |
| `adornment` | `require "adornment"` | the umbrella gem: loads every part |

Everything lives in the `Adornment` namespace.

## The one pitfall: write `Traced()`, not `Traced`

A capitalized name with no arguments and no parentheses is a **constant read** in Ruby: it
declares nothing.

```ruby
Traced          # WRONG: a constant read
def a = 1

Traced()        # right
def b = 1

Traced span: "x" # right: arguments make it a method call
def c = 1
```

Ruby gives no hook for a constant read. The [lint](#lint) finds these after the fact, and
`Adornment.verify_all!` runs it by default.

## Defining types

Core has one kind of annotation: method annotations, written above `def`. Per-parameter metadata
is an extension's own business ([Per-parameter metadata in extensions](#per-parameter-metadata-in-extensions)).

An annotation type is an ordinary named class that includes `Adornment::Annotation[...]`. The
brackets take the type's policies; `Adornment::Annotation[]` takes the defaults, and a bare
`include Adornment::Annotation` raises. Fields are instance variables set by an ordinary
`initialize`: Ruby itself decides what is positional, what is a keyword, what is required and
what the defaults are.

### Method annotation types

```ruby
require "adornment/core"

class Route
  include Adornment::Annotation[repeatable: true] # several per method (default: false)

  attr_reader :path, :verbs

  def initialize(path, verbs: [:GET])  # path positional, verbs a keyword with a default
    @path = path
    @verbs = verbs.map(&:to_sym)       # normalize freely: Adornment freezes afterwards
  end
end

class Raises
  include Adornment::Annotation[targets: [:instance]]

  attr_reader :errors

  def initialize(errors)
    @errors = errors
  end
end

raise unless Route.new("/users").verbs == [:GET]
raise unless Route.new("/users", verbs: ["POST"]) == Route.new("/users", verbs: [:POST])
raise unless Route.new("/x").frozen? && Route.new("/x", verbs: [+"put"]).verbs.frozen?
raise unless Raises.new([KeyError, IndexError]).errors == [KeyError, IndexError]
raise unless Route.repeatable? && Raises.targets == [:instance]
```

Policies of method annotation types (all optional; each `include` stores only what it is given):

| Policy | Values | Default |
|---|---|---|
| `repeatable:` | `true` or `false` | `false` |
| `targets:` | a non-empty subset of `[:instance, :singleton]` | both |

Construction rules:

- Declaration methods (`Route "/users", verbs: [:GET]`) call `Type.new` with the arguments as
  written. Wrong arguments raise Ruby's
  own `ArgumentError` (`wrong number of arguments`, `missing keyword: :path`,
  `unknown keyword: :colour`) from the initializer.
- After `initialize` returns, `new` applies the [freezing rule](#immutability) to every instance
  variable and freezes the instance. Do not freeze in the initializer: an instance that is already
  frozen is kept as it is, and deep freezing is then the initializer's job.
- Every instance variable is a field: it takes part in `==` (same class, equal fields), `eql?`,
  `hash`, `to_h`, inspection (`#<Route path="/users", verbs=[:GET]>`) and pattern matching
  (`in { path: String => path }`). Keep helpers and caches out of instance variables.
- There is no `with`: build a new instance.
- `Type[...]` is not a constructor: it raises `Adornment::TargetError`, which shows the call form
  (`Get["/x"]` → `Get("/x")`), so a misplaced bracket form fails loudly.
- Subclasses inherit the policies. A subclass may include `Adornment::Annotation[...]` again to
  override some of them: values replace inherited ones (arrays are not concatenated).

## Activating a class or module

```ruby
require "adornment/core"
class Traced
  include Adornment::Annotation[]

  attr_reader :span

  def initialize(span: nil)
    @span = span
  end
end

class A
  include Adornment[Traced]          # declaration method named after the type: Traced(...)
  Traced(span: "a")
  def a = 1
end

class B
  include Adornment[Trace: Traced]   # an alias names the declaration method
  Trace(span: "b")
  def b = 1
end

class C
  include Adornment[]                # no declaration methods
  adorn Traced.new(span: "c")        # instances only: build them first, reuse them freely
  def c = 1
end

class D
  extend Adornment::Core::Target           # the explicit, low-level form
  use_annotations Traced
end

raise unless [A.annotations_for(:a), B.annotations_for(:b), C.annotations_for(:c)].map { |l| l.first.span } == %w[a b c]
raise unless !Object.respond_to?(:Traced) # nothing is defined globally
```

- Declaration methods are singleton methods of the owner, and its subclasses inherit them.
  Nothing is added to `Object`, `Module` or unrelated classes.
- `include Adornment` (bare), `extend Adornment[...]` and `prepend Adornment[...]` raise
  `ArgumentError`.
- A class that is not an annotation type raises `ArgumentError` ("X is not an annotation type;
  include Adornment::Annotation[...]"); so does `adorn Route` (a type, not an instance: write
  `adorn Route.new(...)`) and `adorn` with any object that is not an annotation instance.
- A declaration method `Route("/x")` is `adorn Route.new("/x")`: both record the user's line
  once, and the declaration's location travels with it until it attaches.

## Which definitions take a declaration

Pending declarations attach, in order, to the **next method definition in the same owner, made
from the same fiber**, whatever makes that definition.

| Construct | Takes the declarations? |
|---|---|
| `def`, endless `def`, `private def`, `protected def`, `def` in `class_eval` (string or block) | yes |
| `define_method` with a block, Proc, Method or UnboundMethod | yes |
| `def self.x`, `define_singleton_method` | yes, on the singleton side (unless the type narrows `targets` to `:instance`) |
| `attr_reader`, `attr_writer`, `attr_accessor` | yes: the first method generated (`a` for `attr_accessor :a`) |
| `alias`, `alias_method` (also in `class << self`) | yes: an alias is annotated like any method (see [Aliases](#aliases)) |
| `private :inherited_method`, `private_class_method :inherited`, `module_function :inherited` | yes: Ruby makes an own entry in this owner, an override that runs the ancestor's body |
| `module_function :name` singleton copy | yes, on the singleton side: a copy, like an alias (the instance method keeps its own) |
| any other method defined in between, e.g. by a macro | **yes** |

- A definition takes the pending declarations; a definition with nothing pending changes
  nothing. Redefining a method with declarations replaces its annotations; redefining it without
  declarations keeps them. Removal is not tracked: after `remove_method` or `undef_method` the
  method's annotations are hidden from reflection while the owner does not define it, and an
  unannotated redefinition shows them again. Pending declarations are untouched by removals.
- A non-repeatable type declared twice for one method raises `Adornment::DuplicateAnnotation`.
  A type declared for the wrong kind of method raises `Adornment::InvalidTarget`. Both clear the
  pending declarations.
- Hooks: core prepends `method_added`, `singleton_method_added` and `const_added` to an
  activated owner's singleton class, once per ancestry (subclasses inherit them). Like any Ruby
  hook, an owner's own `self.method_added` must call `super`. A subclass's own hook runs before
  the inherited one, so a declaration it makes before `super` attaches to the method being
  defined.

A declaration cannot reach methods generated by a macro or the second name of an
`attr_reader :a, :b`; to annotate such a method, define it with `def` or `define_method`.

### Aliases

An alias starts with no annotations (nothing is copied from the original) and takes the
declarations above it like any definition, whether it comes from `alias`, `alias_method` or
`define_method(name, instance_method(other))`. An alias has the original's body, so it shares
the original's signature, but not its annotations: an alias that needs a parameter declaration
takes its own above it.

```ruby
require "adornment/core"
class Route
  include Adornment::Annotation[]

  attr_reader :path

  def initialize(path)
    @path = path
  end
end

class UsersApi
  include Adornment[Route]

  Route("/users/:id")
  def show(id) = id

  Route("/profile/:id")       # attaches to profile only
  alias_method :profile, :show

  alias helper show           # unannotated: a plain Ruby method
end

raise unless UsersApi.annotations_for(:show) == [Route.new("/users/:id")]
raise unless UsersApi.annotations_for(:profile) == [Route.new("/profile/:id")]
raise unless UsersApi.annotations_for(:helper).empty?
```

## Leftovers: declarations that never attach

Pending declarations belong to one owner and wait for that owner's
next method definition. Nothing traces body ends, so these raise `Adornment::LeftoverAnnotations`,
naming the owner, the annotation and where it was declared, and clear the pending declarations:

- a declaration on another owner while declarations are still pending;
- a constant added to the owner while it has pending declarations (a nested `class Inner`,
  `LIMIT = 10`).

A leftover at the end of a body is not raised there, so it never masks an exception unwinding the
body. It stays pending until one of the above, the owner's next definition (also in a later
reopening) or verification. `Owner.verify_adornments!` checks one owner and
`Adornment.verify_all!` checks everything pending. Call it once your code is loaded, for example
at the end of boot or in a test.

```ruby
require "adornment/core"
class Tag
  include Adornment::Annotation[]

  attr_reader :name

  def initialize(name)
    @name = name
  end
end

begin
  class Service
    include Adornment[Tag]
    Tag("fetch")
    class Inner; end # const_added(:Inner) while Tag is pending
    def fetch = 1
  end
rescue Adornment::LeftoverAnnotations => e
  raise unless e.leftovers.keys == [Service] && e.message.include?("declared at")
end

Built = Class.new { include Adornment[Tag]; Tag("in a block body") }
begin
  Class.new { include Adornment[Tag]; Tag("another owner") }
  raise "expected a leftover"
rescue Adornment::LeftoverAnnotations => e
  raise unless e.leftovers.keys == [Built]
end
```

## Reflection

```ruby
require "adornment/core"
class Traced
  include Adornment::Annotation[]

  attr_reader :span

  def initialize(span: nil)
    @span = span
  end
end

class Tag
  include Adornment::Annotation[repeatable: true]

  attr_reader :name

  def initialize(name)
    @name = name
  end
end

class Parent
  include Adornment[Traced, Tag]

  Traced(span: "p")
  Tag("a")
  Tag("b")
  def fetch = 1
end

class Child < Parent
  def fetch = super # unannotated override
end

class Heir < Parent; end # no override: Parent#fetch is the resolved method

raise unless Parent.annotation(:fetch, Traced) == Traced.new(span: "p")
raise unless Parent.annotated_with(Tag) == { fetch: [Tag.new("a"), Tag.new("b")] }
raise unless Heir.annotation(:fetch, Traced) == Traced.new(span: "p")
raise unless Child.annotations_for(:fetch).empty? && Child.annotation(:fetch, Traced).nil? # strict
raise unless Child.find_annotation(:fetch, Traced) == Traced.new(span: "p")               # walks ancestors
raise unless Child.declarations_for(:fetch).all? { |d| d.owner == Parent && !d.resolved }
```

| Owner method | Returns |
|---|---|
| `annotations_for(name, type = nil, singleton: false)` | the resolved method's annotations |
| `annotation(name, type, singleton: false)` | the resolved method's annotation of `type`, or nil (raises for repeatable types) |
| `find_annotation(name, type, singleton: false)` | the same, falling back to the nearest overridden method that has one (raises for repeatable types) |
| `annotated_with(type, singleton: false)` | `{name => annotation}`, or `{name => [annotations]}` for repeatable types |
| `own_annotations_for(name, type = nil, singleton: false)` | only this owner's annotations |
| `own_annotated_methods(singleton: false)` | the names this owner annotated and still defines, in first-annotation order |
| `declarations_for(name, singleton: false)` | every `Adornment::Core::Declaration` (`annotation`, `owner`, `method_name`, `singleton`, `resolved`) along the ancestors |
| `pending_adornments` | annotations still waiting for a definition (current fiber) |

- Everything is relative to the **resolved method**: the body Ruby's lookup reaches. Its owner is
  the defining owner, so for a method from an included module, the module.
- Queries are strict, as in Java: an override does not carry the annotations of the method it
  overrides. `find_annotation` walks the overridden methods, nearest first (like Spring's
  `findAnnotation`); `declarations_for` lists all of them.
- A visibility change (`private :fetch` in a subclass) is an override like any other: it has its
  own annotations (none unless declared), and `find_annotation` reaches the parent's.
  `undef_method` stops reflection; `remove_method` falls through to ancestors.
- Classes and modules that include, prepend or extend an activated module get this read-only API
  automatically, without declaration methods.
- Results are frozen. Reflection never locks. It is meant for boot and compilation, not for each
  request: extensions compile what they need once.

### Discovery

`Adornment.annotated_with(type, singleton: false)` searches every registered owner and returns the
*defining* owners: `{Owner => {name => annotation(s)}}`. Owners that only inherit annotated
methods are not listed; ask them with `Owner.annotated_with(type)`. Load your code first: a class
that was never loaded cannot be found. `Adornment.registered_owners` lists the activated owners
that are still reachable. The registry holds them weakly, so dropped classes can be collected.

```ruby
require "adornment/core"
class Route
  include Adornment::Annotation[]

  attr_reader :path

  def initialize(path)
    @path = path
  end
end

class Users
  include Adornment[Route]
  Route("/users")
  def index = 1
end

class Admins < Users; end # inherits index, declares nothing

raise unless Adornment.annotated_with(Route) == { Users => { index: Route.new("/users") } }
raise unless Admins.annotated_with(Route) == { index: Route.new("/users") }
Adornment.unregister(Users)
raise unless Adornment.annotated_with(Route).empty? && Users.annotations_for(:index) == [Route.new("/users")]
```

`Adornment.unregister(owner)` only removes the owner from discovery and from `verify_all!`. Its
hooks stay installed and its metadata stays readable through its own reflection API. Declaring on
it again does not register it again; activating it again (`include Adornment[...]`) does.

## Attachment-time validation

An annotation type may define `validate(site)`. It runs whenever an annotation of the type is
about to attach, after the target and duplicate checks and before anything is written; it reads
and raises, never mutates. `site` answers `owner`, `name`, `method` (an `UnboundMethod`),
`annotations` (the complete proposed set, frozen), `instance?` and `singleton?`. One site is
shared by every annotation of the definition.

```ruby
require "adornment/core"

class Reader
  include Adornment::Annotation[]

  def validate(site)
    raise ArgumentError, "annotates a reader without parameters" unless site.method.parameters.empty?
    raise ArgumentError, "cannot be combined with Writer" if site.annotations.any?(Writer)
  end
end

class Writer
  include Adornment::Annotation[]
end

class Model
  include Adornment[Reader, Writer]

  Reader()
  def name = "n"
end

begin
  Model.class_eval do
    Reader()
    def age(unit) = unit
  end
rescue Adornment::DefinitionError => e
  raise unless e.message.start_with?("Model#age: annotates a reader") && e.cause.is_a?(ArgumentError)
end
raise unless Model.annotations_for(:age).empty? && Model.pending_adornments.empty?

begin
  Model.class_eval do
    Reader()
    Writer()
    def title = "t"
  end
rescue Adornment::DefinitionError => e
  raise unless e.message.include?("cannot be combined")
end
raise unless Model.annotations_for(:title).empty?
```

- Every `StandardError` from a validator becomes `Adornment::DefinitionError`, with the original
  as `cause`. The message starts with `Owner#method` (`Owner.method` for singleton methods) and
  ends with `(declared at path:line)`; that location is also the first backtrace entry.
- On failure nothing is attached and no declaration stays pending; the method itself stays
  defined, and defining it again (with or without declarations) works as usual.
- Validators run outside the owner's lock.

## Per-parameter metadata in extensions

Core has no parameter annotations: no attachment, signature checking or resolution for
parameters. An extension that needs per-parameter metadata keeps its own ordinary value objects
inside one of its method annotations, and reads them back with the reflection API and Ruby's
`Method#parameters`. adornment-api's `Params` is built this way; the minimal form is:

```ruby
require "adornment/core"

module Vocabulary
  # Ordinary metadata: core knows nothing about it.
  Query = Data.define(:type, :default) do
    def initialize(type:, default: nil) = super
  end
end

class Args # the extension's own declaration
  include Adornment::Annotation[]

  attr_reader :parameters

  def initialize(parameters)
    @parameters = parameters
  end
end

class Items
  include Vocabulary                      # makes Query resolvable, as for any constant
  include Adornment[Args]

  Args({ page: Query.new(Integer, 1), per: Query.new(Integer) })
  def index(page:, per: 20) = [page, per]
end

declared = Items.annotation(:index, Args).parameters
raise unless declared == { page: Vocabulary::Query.new(Integer, 1), per: Vocabulary::Query.new(Integer) }
raise unless declared.frozen?                                        # the freezing rule
raise unless Items.instance_method(:index).parameters == [%i[keyreq page], %i[key per]]
raise unless Items.new.index(page: 2) == [2, 20]                    # core never touches the method
```

- Everything here is plain core: the declaration is an ordinary method annotation (attached to the
  next definition, strict reflection, non-repeatable unless the type says otherwise), and its
  values follow the [freezing rule](#immutability): the Hash is copied and frozen, the metadata
  objects are kept as they are (make them immutable yourself, as `Data` is).
- The metadata objects are not annotations: `adorn`, `include Adornment[...]` and
  `annotated_with` reject them.
- What the declaration means (which parameters it must cover, what a missing value becomes, how
  values are resolved) is the extension's decision; core reads no source files and never looks at
  signature defaults.
- An extension checks a declaration against the method in its type's `validate(site)` (see
  [Attachment-time validation](#attachment-time-validation)), or from its own `method_added` hook
  on the classes it activates (calling `super`, as for any hook), using `pending_adornments`
  before `super` and reflection after it.

## Lint

`Adornment.lint(*owners_or_paths)` parses source with Prism. It flags statements that sit directly
in a class or module body, consist only of a constant (`Traced` or `A::Traced`), and match a
declaration method or type registered on that owner. It evaluates nothing and cannot know intent.
Suppress a diagnostic with `# adornment:ignore` on the same line.

`Adornment.verify_all!(lint: :warn)` runs it. `:warn` (the default) prints the diagnostics,
`:error` raises `Adornment::LintError`, and `false` skips the lint.

## Public API

This is the supported surface. Extension gems need nothing else, and
[`examples/events`](examples/events/events.rb) is a working extension that uses only this.

**`Adornment.*`** (all declared in `lib/adornment/core.rb`):

| | |
|---|---|
| `Adornment[*types, **aliases]` | a module whose `include` activates the includer |
| `activated?(owner)` | whether `owner` (or an ancestor) is activated |
| `annotated_with(type, singleton: false)` | global discovery over registered owners |
| `registered_owners` | the registered, reachable owners |
| `verify_all!(lint: :warn)` | report every leftover (and lint) at once |
| `lint(*owners_or_paths)` | the bare-constant lint |
| `unregister(owner)` | remove an owner from discovery and verification |
| `immutable_copy(value)` | the freezing rule, for extension values |

**Owner API:** `Adornment::Core::Target` provides `use_annotations`, `adorn` and
`verify_adornments!`. Activation also extends the owner with `Adornment::Core::Reflection`,
which provides `annotations_for`, `own_annotations_for`, `annotation`, `find_annotation`,
`annotated_with`, `own_annotated_methods`, `declarations_for` and `pending_adornments`.
Declaration methods (`Traced(...)`) are defined per owner.

**Types:** `Adornment::Annotation[...]` defines an annotation type (included in a plain class);
`Adornment::Annotation` is also the marker module of its instances. Every type answers
`short_name`, `new` (Ruby's construction, then the freezing rule), `repeatable?`, `targets` and
`[]` (raises `TargetError`). Instances answer `validate(site)` (a no-op unless the type defines
it), `==`, `eql?`, `hash`, `to_h` and `deconstruct_keys`.

**Records:** `Adornment::Core::Declaration`, `Adornment::Core::Pending::PendingDeclaration`
(`annotation`, `location`), `Adornment::Core::Site` and `Adornment::Core::Lint::Diagnostic`.
`Adornment[...]` returns an `Adornment::Core::Base`.

**Errors:** `Adornment::Error`, with the subclasses `DuplicateAnnotation`, `InvalidTarget`,
`TargetError`, `DefinitionError`, `LeftoverAnnotations` (`leftovers`) and `LintError`
(`diagnostics`), plus
`Adornment::UnsupportedPlatformError` (a `LoadError`).

The names users write every day (`Adornment[...]`, `Adornment::Annotation`, the errors) live
directly under `Adornment`; the owner API and records above live under `Adornment::Core`.
Everything else under `Adornment::Core` (state, registry, hooks, pending store) is internal and
may change in any release.

## Threads, fibers and immutability

- Pending declarations are **fiber-local**, keyed by the owner (by identity); one owner at a time
  per fiber.
- Reflection never locks: entries are frozen Arrays, and whole-side reads get a frozen snapshot.
  Writes take the owner's lock. No user code runs under it.
- Defining annotated methods on one class from several threads at once does not lose or corrupt
  registrations, but the ordering is unspecified. **Concurrent definition is unsupported.**

### Immutability

Annotation instances are frozen. Array, Hash, Set and String values are stored as deep-frozen
copies, so your objects are never mutated or frozen. A value that is already deeply immutable
(`Ractor.shareable?`) is kept as it is. Other objects are kept by reference. Use
`Ractor.shareable?(annotation)` if you need full shareability.

The rule is applied by `new` after the initializer returns, to every instance variable: so it
covers what the initializer builds while normalizing (`@values = values.map(&:to_s)` stores a
frozen Array of frozen Strings). Defaults written in the initializer are copied like any value;
a frozen constant default is kept as it is. An initializer that freezes the instance itself opts
out: the instance is then kept as it is.

## How it works, and what it costs

- Definitions are observed through `method_added`, `singleton_method_added` and `const_added` of
  activated owners only.
- A definition with no pending declaration for its owner takes a path that allocates nothing and
  looks up no method body. A definition on an activated owner costs well under a microsecond more
  than on a plain class; see [benchmarks](docs/benchmarks.md).
- Nothing is traced: no TracePoint is ever enabled. Leftovers are found by the next declaration
  on another owner, by `const_added` on the owner, or by verification.
- Calls to annotated methods run the method itself. The specs check owner, source location, zero
  extra allocations, and that no Adornment code runs during calls.
- `require "adornment/core"` loads only the declaration and reflection engine. The lint (and
  Prism) is autoloaded on first use.

[docs/architecture.md](docs/architecture.md) explains the internals and the techniques taken from
sorbet-runtime.

## Limitations

1. **CRuby only.** Lock-free reads rely on GVL-atomic `Hash#[]` with Symbol keys.
2. **A leftover at the end of a body is not reported there.** It is reported by the next
   declaration on another owner, a constant added to the owner, or verification; until then it
   attaches to the owner's next definition from the same fiber, also in a later reopening.
3. **Reopening an existing nested class** (`class Inner` when `Inner` is already defined) adds no
   constant, so it does not report the outer owner's pending declarations. Declarations left in a
   fiber that finishes are dropped with it.
4. **A macro between a declaration and its `def`** takes the declaration if it defines a method.
5. **`attr_*` with several names** attaches to the first generated method only.
6. **Concurrent definition** of one owner from several threads is unsupported. Pending
   declarations are fiber-local, so other fibers and threads never see them.
7. **No per-parameter metadata.** Core neither attaches nor checks anything per parameter;
   extensions do (see [Per-parameter metadata in extensions](#per-parameter-metadata-in-extensions)).
8. **Validators see attachments, not every redefinition.** An unannotated redefinition keeps the
   old annotations without running `validate` again; check what matters again where you compile.

## Ruby versions

Declared: CRuby >= 3.3 (`required_ruby_version`). Actually tested for this release:

| Ruby | YJIT off | YJIT on | where |
|---|---|---|---|
| 4.0.5 (arm64-darwin25) | full suite | full suite | local |
| 3.4.11 (`ruby:3.4-slim`, aarch64-linux) | full suite | full suite | Docker |
| 3.3.12 (`ruby:3.3-slim`, aarch64-linux) | full suite | full suite | Docker |

See [docs/testing.md](docs/testing.md) for the exact versions, commands and results. Other
engines raise `Adornment::UnsupportedPlatformError` on require.

## Development

```bash
bundle install
bundle exec rake                       # specs
BUNDLE_WITH=tooling bundle install     # once, for RuboCop (an optional Gemfile group)
BUNDLE_WITH=tooling bundle exec rubocop
ruby benchmarks/compare.rb             # speed against the recorded baseline (RECORD=1 to re-record)
ruby benchmarks/memory_compare.rb      # retained memory against the recorded baseline
```

## License

MIT

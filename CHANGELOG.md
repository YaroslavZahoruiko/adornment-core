# Changelog

## 0.1.0 (2026-10-20)

First release of `adornment-core`, the annotation engine behind Adornment.

- **Annotation types** are named plain classes that include `Adornment::Annotation[...]`, with
  the policies `repeatable:` (default `false`) and `targets:` (default
  `[:instance, :singleton]`). Fields are instance variables set by an ordinary `initialize`, so
  Ruby's own rules decide positional, keyword, required and default arguments. `new` deep-freezes
  copies of Array, Hash, Set and String fields and freezes the instance. Instances compare, hash,
  convert (`to_h`), inspect and pattern-match by class and fields.
- **Declarations** above `def`: `include Adornment[Traced, Cache: Cached]` defines declaration
  methods (`Traced(...)`) on the owner, `adorn instance` declares without them, and
  `extend Adornment::Core::Target` + `use_annotations` is the explicit form. Pending
  declarations attach to the owner's next method definition from the same fiber: `def`,
  `define_method`, `def self.x`, `attr_*` (first name), aliases, `module_function` copies and
  visibility changes of inherited methods.
- **Attachment-time validation**: `Annotation#validate(site)` with `Adornment::Core::Site`; a
  failure raises `Adornment::DefinitionError` (the validator's error as `cause`) and attaches
  nothing.
- **Reflection** along Ruby's method resolution, strict as in Java: `annotations_for`,
  `annotation`, `find_annotation` (walks overridden methods), `annotated_with`,
  `own_annotations_for`, `own_annotated_methods`, `declarations_for`, `pending_adornments`.
  Includers, prependers and extenders of activated modules get the read-only API.
- **Discovery and verification**: `Adornment.annotated_with`, `registered_owners` (weak registry),
  `unregister`, `verify_all!`, `Owner.verify_adornments!`. Leftover declarations raise
  `Adornment::LeftoverAnnotations` on a declaration for another owner, on a constant added to the
  owner, or at verification. Nothing is traced.
- **Lint** for bare annotation constants (`Traced` instead of `Traced()`), parsed with Prism and
  loaded only on first use.
- `Adornment.immutable_copy` and `Type.short_name` for extension gems.
- Never wraps or replaces methods: a call to an annotated method runs no Adornment code and
  allocates nothing extra. Pure Ruby, no runtime dependencies, CRuby >= 3.3.

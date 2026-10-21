# frozen_string_literal: true

require_relative "lib/adornment/core/version"

Gem::Specification.new do |spec|
  spec.name = "adornment-core"
  spec.version = Adornment::Core::VERSION
  spec.authors = ["Yaroslav Zahoruiko"]
  spec.email = ["zahoruiko.yaroslav@gmail.com"]

  spec.summary = "Declarative method annotations and metadata for Ruby."
  spec.description = <<~DESC
    Adornment Core provides declarative method annotations for Ruby.
    Define annotation types, attach immutable metadata to the next method
    definition, and inspect annotations along Ruby's method lookup chain.
    Detects annotation declarations left without a method.

    Pure Ruby with no runtime dependencies. Does not wrap or replace methods.
    Supports CRuby 3.3 and later.
  DESC
  spec.homepage = "https://github.com/YaroslavZahoruiko/adornment-core"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]
end

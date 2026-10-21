# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"
# Lint only: `BUNDLE_WITH=tooling bundle install` (RuboCop's parser builds a C extension).
group :tooling, optional: true do
  gem "rubocop", "~> 1.90"
end

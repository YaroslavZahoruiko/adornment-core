# frozen_string_literal: true

module Adornment
  module Core
    # Heuristic lint for bare annotation constants (loaded on first use).
    #
    # A line holding only `Traced` inside a class body is a constant read: it declares nothing. The
    # lint parses source files with Prism and flags statements directly in a `class` or `module`
    # body that consist only of a constant read or constant path whose text matches a declaration
    # method or type registered on that owner. It evaluates nothing and cannot know intent. A
    # `# adornment:ignore` comment on the statement's line suppresses its diagnostic.
    module Lint
      # A comment on a statement's line that suppresses its diagnostic.
      IGNORE = /#\s*adornment:ignore\b/

      # The LoadError message when Prism is not available.
      PRISM_MISSING = "the adornment lint reads source with Prism: Ruby 3.3+ ships it as a default gem; " \
                      "on other Rubies add gem \"prism\" to your Gemfile"

      # One possible mistake.
      #
      # @!attribute [r] path
      #   @return [String]
      # @!attribute [r] line
      #   @return [Integer]
      # @!attribute [r] owner
      #   @return [String] the enclosing class or module as written in the source
      # @!attribute [r] constant
      #   @return [String] the flagged text
      Diagnostic = Data.define(:path, :line, :owner, :constant) do
        # @return [String]
        def message
          "`#{constant}` alone is a constant read and declares nothing; did you mean `#{constant}()`? " \
            "(add `# adornment:ignore` if intended)"
        end

        # @return [String]
        def to_s = "#{path}:#{line}: in #{owner}: #{message}"
      end

      class << self
        # Lints the files that define `targets`: owners are mapped to their source files, Strings
        # are file paths; every file is parsed once.
        # @param targets [Array<Module, String>] registered owners or file paths
        # @return [Array<Diagnostic>]
        # @raise [LoadError] when Prism cannot be loaded
        def run(targets)
          load_prism
          owners = Core::Registry.owners
          by_name = owners.select(&:name).to_h { |o| [o.name, o] }
          fallback = owners.flat_map { |o| names_for(o) }.uniq
          files = targets.flat_map { |t| t.is_a?(Module) ? files_for(t) : [File.expand_path(t.to_s)] }.uniq
          files.select { |f| File.file?(f) }.flat_map { |f| lint_file(f, by_name, fallback) }
        end

        # Requires Prism unless it is loaded already.
        # @api private
        # @return [void]
        # @raise [LoadError] with {PRISM_MISSING}
        def load_prism
          return if defined?(::Prism.parse_file)

          require "prism"
        rescue LoadError
          raise LoadError, PRISM_MISSING
        end

        # Files that define `owner`: its constant location and its methods' source locations.
        # Sources that are not files (eval strings) are skipped.
        # @api private
        # @param owner [Module]
        # @return [Array<String>] existing file paths
        def files_for(owner)
          paths = []
          if owner.name
            loc = begin
              Object.const_source_location(owner.name)
            rescue NameError
              nil
            end
            paths << loc[0] if loc && !loc.empty?
          end
          [owner, owner.singleton_class].each do |mod|
            (mod.instance_methods(false) + mod.private_instance_methods(false)).each do |name|
              loc = mod.instance_method(name).source_location
              paths << loc[0] if loc
            end
          end
          paths.uniq.select { |p| File.file?(p) }
        end

        # Declaration method names (aliases included) and full type names of the method annotations
        # usable on `owner`.
        # @api private
        # @param owner [Module]
        # @return [Array<String>]
        def names_for(owner)
          Core::AnnotationMethods.types_of(owner).flat_map { |name, type| [name.to_s, type.name].compact }.uniq
        end

        # Parses one file and flags bare constants in class and module bodies.
        # @api private
        # @param path [String]
        # @param by_name [Hash{String => Module}] registered owners by constant name
        # @param fallback [Array<String>] names checked in bodies of unregistered owners
        # @return [Array<Diagnostic>]
        def lint_file(path, by_name, fallback)
          result = Prism.parse_file(path)
          ignored = result.comments.filter_map { |c| c.location.start_line if c.location.slice.match?(IGNORE) }
          found = []
          walk(result.value, [], by_name) do |statements, owner_name, owner|
            names = owner ? names_for(owner) : fallback
            statements.each do |node|
              next unless %i[constant_read_node constant_path_node].include?(node.type)
              next unless names.include?(node.slice)
              next if ignored.include?(node.location.start_line)

              found << Diagnostic.new(path: path, line: node.location.start_line, owner: owner_name, constant: node.slice)
            end
          end
          found
        end

        # Yields each class or module body's statement list with its owner name and registered
        # owner.
        # @api private
        # @param node [Prism::Node]
        # @param nesting [Array<String>] the enclosing constant paths
        # @param by_name [Hash{String => Module}]
        # @yieldparam statements [Array<Prism::Node>]
        # @yieldparam owner_name [String] the nesting as written, joined with `::`
        # @yieldparam owner [Module, nil] the registered owner of that name
        # @return [void]
        def walk(node, nesting, by_name, &)
          return unless node.is_a?(Prism::Node)

          if %i[class_node module_node].include?(node.type)
            inner = nesting + [node.constant_path.slice]
            full = inner.join("::")
            owner = by_name[full] || by_name[node.constant_path.slice]
            yield(node.body.body, full, owner) if node.body&.type == :statements_node
            node.body&.compact_child_nodes&.each { |child| walk(child, inner, by_name, &) }
          else
            node.compact_child_nodes.each { |child| walk(child, nesting, by_name, &) }
          end
        end
      end
    end
  end
end

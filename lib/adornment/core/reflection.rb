# frozen_string_literal: true

module Adornment
  module Core
    # One declaration found along a method's ancestor chain (see {Reflection#declarations_for}).
    #
    # @!attribute [r] annotation
    #   @return [Adornment::Annotation]
    # @!attribute [r] owner
    #   @return [Module] the class or module that declared it
    # @!attribute [r] method_name
    #   @return [Symbol]
    # @!attribute [r] singleton
    #   @return [Boolean] whether it annotates a singleton method of `owner`
    # @!attribute [r] resolved
    #   @return [Boolean] whether it is attached to the method Ruby's lookup reaches
    Declaration = Data.define(:annotation, :owner, :method_name, :singleton, :resolved)

    # Owner API for reading annotations. Activated owners have it through {Target}; classes and
    # modules that include, prepend or extend an activated module receive it automatically.
    #
    # Queries read annotations from the *resolved method*: the method Ruby would call for
    # the given name. An override does not inherit annotations from the method it replaces.
    # {#find_annotation} and {#declarations_for} also search overridden methods along the
    # ancestor chain. Query results are frozen.
    module Reflection
      # Annotations of the resolved method.
      #
      # @param name [Symbol, String]
      # @param type [Class, nil] only annotations that are `is_a?(type)`
      # @param singleton [Boolean] query the singleton method
      # @return [Array<Adornment::Annotation>] frozen, in declaration order
      def annotations_for(name, type = nil, singleton: false)
        Core::Query.annotations_for(self, name.to_sym, type, singleton)
      end

      # Every declaration for `name` along the ancestor chain, nearest owner first.
      #
      # @param name [Symbol, String]
      # @param singleton [Boolean] walk the singleton method
      # @return [Array<Adornment::Core::Declaration>] frozen; the resolved method's come first, with
      #   `resolved: true`
      def declarations_for(name, singleton: false)
        name = name.to_sym
        result = []
        resolved = true
        Core::Query.each_entry(self, name, singleton) do |holder, side, annotations|
          annotations.each do |annotation|
            result << Declaration.new(annotation: annotation, owner: holder, method_name: name,
                                      singleton: side == :singleton, resolved: resolved)
          end
          resolved = false
        end
        result.freeze
      end

      # The annotation of `type` on the resolved method, or nil.
      #
      # @param name [Symbol, String]
      # @param type [Class] a non-repeatable annotation type; matches with `is_a?(type)`
      # @param singleton [Boolean] query the singleton method
      # @return [Adornment::Annotation, nil]
      # @raise [ArgumentError] for repeatable types (use {#annotations_for}) or non-annotation types
      def annotation(name, type, singleton: false)
        Core::Utils.check_type!(type)
        raise ArgumentError, "#{type} is repeatable; use annotations_for(name, #{type})" if type.repeatable?

        Core::Query.resolved_entry(self, name.to_sym, singleton).find { |a| a.is_a?(type) }
      end

      # The annotation of `type` on the resolved method or, failing that, on the nearest method it
      # overrides along the ancestor chain; nil when none has one.
      #
      # @param name [Symbol, String]
      # @param type [Class] a non-repeatable annotation type; matches with `is_a?(type)`
      # @param singleton [Boolean] query the singleton method
      # @return [Adornment::Annotation, nil]
      # @raise [ArgumentError] for repeatable types (use {#declarations_for}) or non-annotation
      #   types
      def find_annotation(name, type, singleton: false)
        Core::Utils.check_type!(type)
        raise ArgumentError, "#{type} is repeatable; use declarations_for(name)" if type.repeatable?

        Core::Query.each_entry(self, name.to_sym, singleton) do |_holder, _side, annotations|
          annotations.each { |a| return a if a.is_a?(type) }
        end
        nil
      end

      # Every method whose resolved method is annotated with `type` (see {#annotations_for}),
      # including methods inherited from ancestors.
      #
      # @param type [Class] an annotation type; matches with `is_a?(type)`
      # @param singleton [Boolean] look at singleton methods
      # @return [Hash{Symbol => Adornment::Annotation}] frozen, for non-repeatable types
      # @return [Hash{Symbol => Array<Adornment::Annotation>}] frozen, for repeatable types
      # @raise [ArgumentError] when `type` is not an annotation type
      def annotated_with(type, singleton: false)
        Core::Utils.check_type!(type)
        result = {}
        Core::Query.candidate_names(self, singleton).each do |name|
          found = Core::Query.annotations_for(self, name, type, singleton)
          next if found.empty?

          result[name] = type.repeatable? ? found : found.first
        end
        result.freeze
      end

      # Only the annotations this class or module itself attached to `name`, while it still
      # defines the method.
      #
      # @param name [Symbol, String]
      # @param type [Class, nil] only annotations that are `is_a?(type)`
      # @param singleton [Boolean] query the singleton method
      # @return [Array<Adornment::Annotation>] frozen
      def own_annotations_for(name, type = nil, singleton: false)
        name = name.to_sym
        entry = Core::State.of(self)&.entry(singleton ? :singleton : :instance, name)
        return Core::State::NONE unless entry && Core::Query.own?(singleton ? singleton_class : self, name)

        type ? entry.select { |a| a.is_a?(type) }.freeze : entry
      end

      # The methods this class or module itself annotated and still defines, in the order they were
      # first annotated (re-annotating a method keeps its place).
      #
      # @param singleton [Boolean] list singleton methods
      # @return [Array<Symbol>] frozen
      def own_annotated_methods(singleton: false)
        side = singleton ? :singleton : :instance
        entries = Core::State.of(self)&.entries(side) or return Core::State::NONE
        mod = singleton ? singleton_class : self
        entries.filter_map { |name, annotations| name if !annotations.empty? && Core::Query.own?(mod, name) }.freeze
      end

      # Annotations declared on this owner (in the current fiber) that are still waiting for a
      # definition.
      #
      # @return [Array<Adornment::Annotation>] frozen, in declaration order
      def pending_adornments
        Core::Pending.peek(self).map(&:annotation).freeze
      end
    end
  end
end

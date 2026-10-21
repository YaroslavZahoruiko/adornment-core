# frozen_string_literal: true

module Adornment
  module Core
    # The method annotations are about to attach to, passed to {Annotation#validate}. One site per
    # definition, shared by every annotation in `annotations`, the complete proposed set (frozen).
    class Site
      # @return [Module] the class or module defining the method
      attr_reader :owner
      # @return [Symbol]
      attr_reader :name
      # @return [Array<Adornment::Annotation>] the complete proposed set (frozen)
      attr_reader :annotations

      # @api private
      # @param owner [Module]
      # @param name [Symbol]
      # @param side [:instance, :singleton]
      # @param annotations [Array<Adornment::Annotation>] the complete proposed set (frozen)
      def initialize(owner, name, side, annotations)
        @owner = owner
        @name = name
        @side = side
        @annotations = annotations
      end

      # @note Takes no arguments, unlike `Object#method`, which it replaces on sites.
      # @return [UnboundMethod] the method as defined now
      def method = (singleton? ? @owner.singleton_class : @owner).instance_method(@name)

      # @return [Boolean] whether the method is an instance method of {#owner}
      def instance? = @side == :instance

      # @return [Boolean] whether the method is a singleton method of {#owner}
      def singleton? = @side == :singleton

      # @return [String] `Owner#name` or `Owner.name`
      def label = "#{@owner.inspect}#{singleton? ? '.' : '#'}#{@name}"

      # @return [String] `#<Adornment::Core::Site Owner#name>`
      def inspect = "#<Adornment::Core::Site #{label}>"
      alias to_s inspect
    end
  end
end

# frozen_string_literal: true

# Annotation types shared by the specs.
module SpecTypes
  class Meta
    include Adornment::Annotation[]

    attr_reader :label

    def initialize(label: nil)
      @label = label
    end
  end

  class Tag
    include Adornment::Annotation[repeatable: true]

    attr_reader :name

    def initialize(name:)
      @name = name
    end
  end

  class Traced
    include Adornment::Annotation[]

    attr_reader :span

    def initialize(span: nil)
      @span = span
    end
  end

  class Cached
    include Adornment::Annotation[]

    attr_reader :ttl

    def initialize(ttl: 60)
      @ttl = ttl
    end
  end

  class Local
    include Adornment::Annotation[]
  end

  class InstanceOnly
    include Adornment::Annotation[targets: [:instance]]
  end
end

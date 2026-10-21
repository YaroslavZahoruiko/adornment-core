# frozen_string_literal: true

# Leftovers are never raised at a body end, so they never mask a propagating exception. They
# stay pending until a declaration on another owner, a constant added to the owner, the owner's
# next definition, or verification.
require "English"
RSpec.describe "leftovers and exceptions" do
  def leftover_names(owner)
    owner.verify_adornments!
    []
  rescue Adornment::LeftoverAnnotations => e
    e.leftovers.fetch(owner).map { |p| p.annotation.name }
  end

  it "a body end with a leftover raises nothing; verify names owner, annotation and location" do
    module Fx
      class LeftSubject
        include Adornment[SpecTypes::Tag]

        Tag(name: "left")
      end
    end
    error = begin
      Fx::LeftSubject.verify_adornments!
    rescue StandardError
      $ERROR_INFO
    end
    expect(error.message).to include("Fx::LeftSubject", '#<SpecTypes::Tag name="left">', "#{__FILE__}:")
    expect(error.leftovers.keys).to eq([Fx::LeftSubject])
    expect(idle?).to be(true)
  end

  it "records the declaring line as a String, for declaration methods, adorn and overrides" do
    plain = Class.new { include Adornment[SpecTypes::Tag] }
    overridden = Class.new do
      include Adornment[SpecTypes::Tag]

      # a user override: its own line is the caller
      def self.Tag(**kwargs) = super
    end
    adorn_b = -> (owner) { owner.adorn(SpecTypes::Tag.new(name: "b")) } # its own line is the caller
    line = __LINE__ + 1
    plain.class_eval { Tag(name: "a") }
    adorn_b.call(plain)
    plain.send(:Tag, name: "c")
    plain_error = begin
      plain.verify_adornments!
    rescue StandardError
      $ERROR_INFO
    end
    overridden.class_eval { Tag(name: "d") }
    overridden_error = begin
      overridden.verify_adornments!
    rescue StandardError
      $ERROR_INFO
    end
    expect(plain_error.message).to include("(declared at #{__FILE__}:#{line})")
    locations = [[plain, plain_error], [overridden, overridden_error]].map { |o, e| e.leftovers.fetch(o).map(&:location) }
    expect(locations).to eq([["#{__FILE__}:#{line}", "#{__FILE__}:#{line - 2}", "#{__FILE__}:#{line + 2}"],
                             ["#{__FILE__}:#{overridden.method(:Tag).source_location[1]}"]])
  end

  it "a body that raises propagates its own exception; the leftover is found by verify" do
    expect do
      module Fx
        class R2Subject
          include Adornment[SpecTypes::Tag]

          Tag(name: "t")
          raise "original"
        ensure
          begin
            raise "cleanup"
          rescue RuntimeError
            nil
          end
        end
      end
    end.to raise_error(RuntimeError, "original")
    expect(leftover_names(Fx::R2Subject)).to eq(["t"])
    expect(idle?).to be(true)
  end

  it "a declaration in ensure after the body raised does not mask the exception" do
    expect do
      module Fx
        class R6Subject
          include Adornment[SpecTypes::Tag]

          raise "original"
        ensure
          Tag(name: "t")
        end
      end
    end.to raise_error(RuntimeError, "original")
    expect(leftover_names(Fx::R6Subject)).to eq(["t"])
  end

  it "a block body that raises" do
    owner = nil
    expect do
      Class.new do
        owner = self
        include Adornment[SpecTypes::Tag]

        Tag(name: "t")
        raise "blk"
      end
    end.to raise_error(RuntimeError, "blk")
    expect(leftover_names(owner)).to eq(["t"])
  end

  it "the leftover of an aborted body is reported by the next declaration on another owner" do
    expect do
      module Fx
        class R2cSubject
          include Adornment[SpecTypes::Tag]

          Tag(name: "t")
          raise "aborted"
        end
      end
    end.to raise_error(RuntimeError, "aborted")
    other = activated_class
    expect { other.adorn(SpecTypes::Meta.new) }.to raise_error(Adornment::LeftoverAnnotations, /R2cSubject/)
    expect(idle?).to be(true)
  end
end

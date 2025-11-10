# frozen_string_literal: true

module HasManyProgrammes
  extend ActiveSupport::Concern

  included do
    scope :has_programmes,
          ->(programmes) do
            where(
              "programme_types @> ARRAY[?]::programme_type[]",
              programmes.map(&:type)
            )
          end
  end

  def programmes
    programme_types.map { Programme.new(type: it) }
  end

  def programmes=(value)
    self.programme_types = value.map(&:type).sort.uniq
  end

  def vaccines
    @vaccines ||=
      Vaccine.includes(:programme).where(programme_type: programme_types)
  end
end

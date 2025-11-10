# frozen_string_literal: true

module BelongsToProgramme
  extend ActiveSupport::Concern

  included do
    self.ignored_columns = %w[programme_id]

    scope :where_programme, -> { where(programme_type: it.type) }
  end

  def programme
    if (type = programme_type)
      Programme.new(type:)
    end
  end

  def programme=(value)
    self.programme_type = value&.type
  end
end

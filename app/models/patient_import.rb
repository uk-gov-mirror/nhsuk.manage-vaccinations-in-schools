# frozen_string_literal: true

class PatientImport < ApplicationRecord
  PDS_MATCH_THRESHOLD = 0.7
  CHANGESET_THRESHOLD = 10

  self.abstract_class = true

  has_many :patient_changesets

  def count_column(patient, parents, parent_relationships)
    if patient.new_record? || parents.any?(&:new_record?) ||
         parent_relationships.any?(&:new_record?)
      :new_record_count
    elsif patient.changed? || parents.any?(&:changed?) ||
          parent_relationships.any?(&:changed?)
      :changed_record_count
    else
      :exact_duplicate_record_count
    end
  end

  def validate_pds_match_rate!
    return if valid_pds_match_rate? || changesets.count < CHANGESET_THRESHOLD

    update!(status: :low_pds_match_rate)
  end

  def pds_match_rate
    return 0 if changesets.with_pds_match.count.zero?

    matched = changesets.with_pds_match.count.to_f
    attempted = changesets.with_pds_search_attempted.count

    (matched / attempted * 100).round(2)
  end

  def destroy_parents!
    ActiveRecord::Base.transaction do
      parent_relationships = self.parent_relationships.includes(:parent)

      parents_to_check = self.parent_relationships.map(&:parent)

      parent_relationships.destroy_all

      parents_to_check.each do |parent|
        parent.destroy! if parent.parent_relationships.empty?
      end
    end
  end

  def destroy_parents_without_consent!
    ActiveRecord::Base.transaction do
      parent_relationships =
        self
          .parent_relationships
          .includes(:parent)
          .select { |pr| pr.parent.consents.empty? }

      parents_to_check = self.parent_relationships.map(&:parent)

      parent_relationships.each(&:destroy!)

      parents_to_check.each do |parent|
        parent.destroy! if parent.parent_relationships.empty?
      end
    end
  end

  private

  def check_rows_are_unique
    rows
      .map(&:nhs_number_value)
      .tally
      .each do |nhs_number, count|
        next if nhs_number.nil? || count <= 1

        rows
          .select { _1.nhs_number_value == nhs_number }
          .each do |row|
            row.errors.add(
              :base,
              "The same NHS number appears multiple times in this file."
            )
          end
      end
  end

  def valid_pds_match_rate?
    pds_match_rate / 100 >= PDS_MATCH_THRESHOLD
  end
end

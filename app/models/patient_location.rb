# frozen_string_literal: true

# == Schema Information
#
# Table name: patient_locations
#
#  id            :bigint           not null, primary key
#  academic_year :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  location_id   :bigint           not null
#  patient_id    :bigint           not null
#
# Indexes
#
#  idx_on_location_id_academic_year_patient_id_3237b32fa0    (location_id,academic_year,patient_id) UNIQUE
#  idx_on_patient_id_location_id_academic_year_08a1dc4afe    (patient_id,location_id,academic_year) UNIQUE
#  index_patient_locations_on_location_id                    (location_id)
#  index_patient_locations_on_location_id_and_academic_year  (location_id,academic_year)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (patient_id => patients.id)
#

class PatientLocation < ApplicationRecord
  class ActiveRecord_Relation < ActiveRecord::Relation
    include PatientTeamContributor
  end

  audited associated_with: :patient
  has_associated_audits

  belongs_to :patient
  belongs_to :location

  has_many :sessions,
           -> { where(academic_year: it.academic_year) },
           through: :location,
           class_name: "Session"

  has_one :organisation, through: :location
  has_one :subteam, through: :location
  has_one :team, through: :location

  has_many :attendance_records,
           -> { where(patient_id: it.patient_id) },
           through: :location

  has_many :gillick_assessments,
           -> { where(patient_id: it.patient_id) },
           through: :sessions

  has_many :pre_screenings,
           -> { where(patient_id: it.patient_id) },
           through: :sessions

  has_many :vaccination_records,
           -> { where(patient_id: it.patient_id) },
           through: :sessions

  has_and_belongs_to_many :immunisation_imports

  scope :current, -> { where(academic_year: AcademicYear.current) }
  scope :pending, -> { where(academic_year: AcademicYear.pending) }

  scope :joins_sessions, -> { joins(<<-SQL) }
    INNER JOIN sessions
    ON sessions.location_id = patient_locations.location_id
    AND sessions.academic_year = patient_locations.academic_year
  SQL

  scope :appear_in_programmes,
        ->(programmes) do
          session_programme_exists =
            SessionProgramme
              .where(programme: programmes)
              .joins(:session)
              .where("sessions.location_id = patient_locations.location_id")
              .where("sessions.academic_year = patient_locations.academic_year")
              .arel
              .exists

          location_programme_year_group_exists =
            Location::ProgrammeYearGroup
              .joins(:location_year_group)
              .where(
                "location_year_groups.location_id = patient_locations.location_id"
              )
              .where(
                "location_year_groups.academic_year = patient_locations.academic_year"
              )
              .where(
                "location_year_groups.value = " \
                  "patient_locations.academic_year - patients.birth_academic_year - ?",
                Integer::AGE_CHILDREN_START_SCHOOL
              )
              .where(programme: programmes)
              .arel
              .exists

          where(session_programme_exists).where(
            location_programme_year_group_exists
          )
        end

  scope :destroy_all_if_safe,
        -> do
          includes(
            :attendance_records,
            :gillick_assessments,
            :pre_screenings,
            :vaccination_records
          ).find_each(&:destroy_if_safe!)
        end

  def safe_to_destroy?
    attendance_records.none?(&:attending?) && gillick_assessments.empty? &&
      pre_screenings.empty? && vaccination_records.empty?
  end

  def destroy_if_safe!
    destroy! if safe_to_destroy?
  end

  after_create :sync_to_patient_team
  after_update :sync_to_patient_team_if_changed
  before_destroy :remove_from_patient_team

  private

  def sync_to_patient_team
    Session
      .where(location_id: location_id, academic_year: academic_year)
      .distinct
      .pluck(:team_id)
      .each do |team_id|
        PatientTeam.sync_record(
          PatientTeam.pls_subquery_name,
          patient_id,
          team_id
        )
      end
  end

  def sync_to_patient_team_if_changed
    if saved_change_to_patient_id? || saved_change_to_academic_year? ||
         saved_change_to_location_id?
      old_team_ids =
        Session
          .where(
            location_id: location_id_before_last_save,
            academic_year: academic_year_before_last_save
          )
          .distinct
          .pluck(:team_id)
      new_team_ids =
        Session
          .where(location_id: location_id, academic_year: academic_year)
          .distinct
          .pluck(:team_id)
      unmodified_team_ids = old_team_ids & new_team_ids
      old_team_ids -= unmodified_team_ids
      new_team_ids -= unmodified_team_ids

      old_team_ids.each do |old_team_id|
        PatientTeam.remove_identifier(
          PatientTeam.pls_subquery_name,
          patient_id_before_last_save,
          old_team_id
        )
      end
      new_team_ids.each do |new_team_id|
        PatientTeam.sync_record(
          PatientTeam.pls_subquery_name,
          patient_id,
          new_team_id
        )
      end
    end
  end

  def remove_from_patient_team
    Session
      .where(location_id: location_id, academic_year: academic_year)
      .distinct
      .pluck(:team_id)
      .each do |team_id|
        PatientTeam.remove_identifier(
          PatientTeam.pls_subquery_name,
          patient_id,
          team_id
        )
      end
  end
end

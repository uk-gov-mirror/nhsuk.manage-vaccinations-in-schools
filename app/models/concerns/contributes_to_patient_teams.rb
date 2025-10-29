# frozen_string_literal: true

module ContributesToPatientTeams
  extend ActiveSupport::Concern

  included do
    after_create :after_create_add_source_to_patient_teams
    around_update :after_update_sync_source_of_patient_teams
    before_destroy :before_destroy_remove_source_from_patient_teams
  end

  private

  def after_create_add_source_to_patient_teams
    fetch_source_and_patient_team_ids.each do |source, patient_team_ids|
      patient_team_ids.each do |patient_id, team_id|
        PatientTeam.find_or_initialize_by(patient_id:, team_id:).add_source!(
          source
        )
      end
    end
  end

  def after_update_sync_source_of_patient_teams
    subquery_identifiers = self.class.all.contributing_subqueries.keys

    old_patient_team_ids = fetch_source_and_patient_team_ids
    yield
    new_patient_team_ids = fetch_source_and_patient_team_ids

    unmodified_patient_team_ids =
      subquery_identifiers.index_with do |key|
        old_patient_team_ids[key] & new_patient_team_ids[key]
      end

    removed_patient_team_ids =
      old_patient_team_ids
        .map { |key, value| [key, (value - unmodified_patient_team_ids[key])] }
        .to_h
    inserted_patient_team_ids =
      new_patient_team_ids
        .map { |key, value| [key, (value - unmodified_patient_team_ids[key])] }
        .to_h

    removed_patient_team_ids.each do |source, patient_team_ids|
      patient_team_ids.each do |patient_id, team_id|
        PatientTeam.find_by(patient_id:, team_id:)&.remove_source!(source)
      end
    end

    inserted_patient_team_ids.each do |source, patient_team_ids|
      patient_team_ids.each do |patient_id, team_id|
        PatientTeam.find_or_initialize_by(patient_id:, team_id:).add_source!(
          source
        )
      end
    end
  end

  def before_destroy_remove_source_from_patient_teams
    fetch_source_and_patient_team_ids.each do |source, patient_team_ids|
      patient_team_ids.each do |patient_id, team_id|
        PatientTeam.find_by(patient_id:, team_id:)&.remove_source!(source)
      end
    end
  end

  def fetch_source_and_patient_team_ids
    self
      .class
      .where(id:)
      .contributing_subqueries
      .transform_values do |subquery|
        subquery
          .fetch(:contribution_scope)
          .select(
            "#{subquery.fetch(:patient_id_source)} as patient_id",
            "#{subquery.fetch(:team_id_source)} as team_id"
          )
          .distinct
          .map { [it.patient_id, it.team_id] }
      end
  end
end

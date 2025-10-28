# frozen_string_literal: true

class PatientTeamContributingRecord < ApplicationRecord
  self.abstract_class = true

  class ActiveRecord_Relation < ActiveRecord::Relation
    include PatientTeamContributor
  end

  after_create :after_create_synced_to_patient_teams
  around_update :update_synced_to_patient_teams
  before_destroy :before_delete_synced_to_patient_teams

  private

  def after_create_synced_to_patient_teams
    get_patient_team_pairs.each do |source, pairs|
      pairs.each { |pair| PatientTeam.sync_record(source, pair[0], pair[1]) }
    end
  end

  def update_synced_to_patient_teams
    subquery_identifiers = self.class.all.contributing_subqueries.keys

    old_patient_team_pairs = get_patient_team_pairs
    yield
    new_patient_team_pairs = get_patient_team_pairs

    unmodified_pairs = {}
    subquery_identifiers.each do |key|
      unmodified_pairs.update(
        { key => (old_patient_team_pairs[key] & new_patient_team_pairs[key]) }
      )
    end

    removed_pairs =
      old_patient_team_pairs
        .map { |key, value| [key, (value - unmodified_pairs[key])] }
        .to_h
    inserted_pairs =
      new_patient_team_pairs
        .map { |key, value| [key, (value - unmodified_pairs[key])] }
        .to_h

    removed_pairs.each do |source, pairs|
      pairs.each do |pair|
        PatientTeam.remove_identifier(source, pair[0], pair[0])
      end
    end
    inserted_pairs.each do |source, pairs|
      pairs.each { |pair| PatientTeam.sync_record(source, pair[0], pair[1]) }
    end
  end

  def before_delete_synced_to_patient_teams
    get_patient_team_pairs.each do |source, pairs|
      pairs.each do |pair|
        PatientTeam.remove_identifier(source, pair[0], pair[1])
      end
    end
  end

  def get_patient_team_pairs
    id = attributes.fetch("id")
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
          .map { |rec| [rec.patient_id, rec.team_id] }
      end
  end
end

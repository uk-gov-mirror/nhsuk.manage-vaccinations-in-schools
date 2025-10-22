# frozen_string_literal: true

# == Schema Information
#
# Table name: patient_teams
#
#  sources    :text             not null, is an Array
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  patient_id :bigint           not null, primary key
#  team_id    :bigint           not null, primary key
#
# Indexes
#
#  index_patient_teams_on_patient_id              (patient_id)
#  index_patient_teams_on_patient_id_and_team_id  (patient_id,team_id)
#  index_patient_teams_on_sources                 (sources) USING gin
#  index_patient_teams_on_team_id                 (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (patient_id => patients.id) ON DELETE => cascade
#  fk_rails_...  (team_id => teams.id) ON DELETE => cascade
#
class PatientTeam < ApplicationRecord
  self.primary_key = %i[team_id patient_id]

  belongs_to :patient
  belongs_to :team

  def self.pls_subquery_name = "pls"

  def self.ars_subquery_name = "ars"

  def self.sync_record(
    type,
    patient_id,
    team_id,
    old_patient_id: nil,
    old_team_id: nil
  )
    if old_patient_id && old_team_id &&
         (old_patient_id != patient_id || old_team_id != team_id)
      remove_identifier(type, old_patient_id, old_team_id)
    end

    pt =
      PatientTeam.find_or_initialize_by(
        patient_id: patient_id,
        team_id: team_id
      )
    pt.sources = Array(pt.sources) | [type]
    pt.save!
  end

  def self.remove_identifier(type, patient_id, team_id)
    pt = find_by(patient_id:, team_id:)
    return unless pt

    pt.sources.delete(type)

    pt.sources.empty? ? pt.destroy! : pt.save!
  end
end

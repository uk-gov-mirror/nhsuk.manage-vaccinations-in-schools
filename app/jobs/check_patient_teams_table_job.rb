# frozen_string_literal: true

class CheckPatientTeamsTableJob < ApplicationJob
  queue_as :check_patient_teams_table

  def perform
    actual_records = PatientTeam.pluck(:patient_id, :team_id).to_set
    expected_records = Set.new
    team_ids = Team.pluck(:id)

    expected_records.merge(
      PatientLocation
        .joins_sessions
        .where(sessions: { team_id: team_ids })
        .pluck(:patient_id, "sessions.team_id")
    )

    expected_records.merge(
      ArchiveReason.where(team_id: team_ids).pluck(:patient_id, :team_id)
    )

    expected_records.merge(
      SchoolMove.where(team_id: team_ids).pluck(:patient_id, :team_id)
    )

    expected_records.merge(
      SchoolMove
        .joins(school: :team)
        .where(school: { type: "school" })
        .pluck(:patient_id, "teams.id")
    )

    expected_records.merge(
      VaccinationRecord.joins(session: :team).pluck(:patient_id, "teams.id")
    )

    expected_records.merge(
      VaccinationRecord
        .where(session_id: nil)
        .joins(
          "JOIN organisations ON organisations.ods_code = vaccination_records.performed_ods_code"
        )
        .joins("JOIN teams ON teams.organisation_id = organisations.id")
        .pluck(:patient_id, "teams.id")
    )

    compare_and_log_records(actual_records, expected_records)
  end

  private

  def compare_and_log_records(actual, expected)
    unexpected_records = actual - expected
    missing_records = expected - actual

    Rails.logger.warn(
      "Patient Teams table comparison finished. Found #{unexpected_records.size} unexpected records " \
        "and #{missing_records.size} missing records."
    )

    unexpected_records.each do |patient_id, team_id|
      Rails.logger.info "Unexpected record: patient_id #{patient_id}, team_id #{team_id}"
    end

    missing_records.each do |patient_id, team_id|
      Rails.logger.info "Missing record: patient_id #{patient_id}, team_id #{team_id}"
    end
  end
end

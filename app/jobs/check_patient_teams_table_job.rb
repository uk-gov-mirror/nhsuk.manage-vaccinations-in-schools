# frozen_string_literal: true

class CheckPatientTeamsTableJob < ApplicationJob
  queue_as :check_patient_teams_table

  def perform
    query_actual = "SELECT patient_id, team_id FROM patient_teams"
    query_expected =
      "SELECT patient_locations.patient_id, sessions.team_id
             FROM patient_locations
                     INNER JOIN sessions
                                ON sessions.location_id = patient_locations.location_id
                                    AND sessions.academic_year = patient_locations.academic_year
            UNION
                (SELECT archive_reasons.patient_id, team_id
                FROM archive_reasons)
            UNION
                (SELECT school_moves.patient_id, school_moves.team_id FROM school_moves)
            UNION
                (SELECT school_moves.patient_id, subteams.team_id
                  FROM school_moves
                     INNER JOIN locations on locations.id = school_moves.school_id
                     INNER JOIN subteams on subteams.id = locations.subteam_id
                  WHERE locations.type = 0)
           UNION
                (SELECT vaccination_records.patient_id, teams.id
                  FROM vaccination_records
                     INNER JOIN organisations ON vaccination_records.performed_ods_code = organisations.ods_code
                     INNER JOIN teams on teams.organisation_id = organisations.id
                     LEFT OUTER JOIN sessions ON sessions.id = vaccination_records.session_id
                  WHERE (vaccination_records.session_id IS NOT NULL AND sessions.team_id = teams.id)
                  OR vaccination_records.session_id IS NULL)"

    unexpected_records =
      ActiveRecord::Base.connection.execute(
        "#{query_actual} EXCEPT #{query_expected}"
      )
    missing_records =
      ActiveRecord::Base.connection.execute(
        "#{query_expected} EXCEPT #{query_actual}"
      )

    Rails.logger.warn "Patient Teams table comparison finished. Found #{unexpected_records.count} unexpected records " \
                        "and #{missing_records.count} missing records."

    unexpected_records.each do |record|
      Rails.logger.info "Unexpected record found with patient_id #{record["patient_id"]} and " \
                          "team_id #{record["team_id"]}."
    end
    missing_records.each do |record|
      Rails.logger.info "Missing record for patient_id #{record["patient_id"]} and team_id #{record["team_id"]}"
    end
  end
end

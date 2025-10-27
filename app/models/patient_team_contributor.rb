# frozen_string_literal: true

module PatientTeamContributor
  def contributing_subqueries
    case table_name
    when "patient_locations"
      {
        PatientTeam.patient_location_subquery_name => {
          patient_id_source: "patient_locations.patient_id",
          team_id_source: "sessions.team_id",
          contribution_scope: joins_sessions
        }
      }
    when "archive_reasons"
      {
        PatientTeam.archive_reason_subquery_name => {
          patient_id_source: "archive_reasons.patient_id",
          team_id_source: "archive_reasons.team_id",
          contribution_scope: all
        }
      }
    when "vaccination_records"
      {
        PatientTeam.vaccination_record_session_subquery_name => {
          patient_id_source: "vaccination_records.patient_id",
          team_id_source: "sessions.team_id",
          contribution_scope: joins(:session)
        },
        PatientTeam.vaccination_record_ods_subquery_name => {
          patient_id_source: "vaccination_records.patient_id",
          team_id_source: "tms.id",
          contribution_scope: joins(join_teams_to_vaccinations_via_organisation)
        }
      }
    when "school_moves"
      {
        PatientTeam.school_move_subquery_name => {
          patient_id_source: "school_moves.patient_id",
          team_id_source: "school_moves.team_id",
          contribution_scope: where("school_moves.team_id IS NOT NULL")
        },
        PatientTeam.school_move_location_subquery_name => {
          patient_id_source: "school_moves.patient_id",
          team_id_source: "stm.team_id",
          contribution_scope:
            joins(join_subteams_to_school_moves_via_location).where(
              "loc.type = 0"
            )
        }
      }
    when "sessions"
      {
        PatientTeam.patient_location_subquery_name => {
          patient_id_source: "patient_locations.patient_id",
          team_id_source: "sessions.team_id",
          contribution_scope: joins_patient_locations
        },
        PatientTeam.vaccination_record_session_subquery_name => {
          patient_id_source: "vaccination_records.patient_id",
          team_id_source: "sessions.team_id",
          contribution_scope: joins(:vaccination_records)
        }
      }
    when "organisations"
      {
        PatientTeam.vaccination_record_ods_subquery_name => {
          patient_id_source: "vacs.patient_id",
          team_id_source: "teams.id",
          contribution_scope:
            joins(join_vaccination_records_to_organisation).joins(:teams)
        }
      }
    when "teams"
      {
        PatientTeam.vaccination_record_ods_subquery_name => {
          patient_id_source: "vacs.patient_id",
          team_id_source: "teams.id",
          contribution_scope:
            joins(:organisation).joins(join_vaccination_records_to_organisation)
        }
      }
    when "locations"
      {
        PatientTeam.school_move_location_subquery_name => {
          patient_id_source: "schlm.patient_id",
          team_id_source: "subteams.team_id",
          contribution_scope:
            joins(:subteam).joins(join_school_moves_to_location).where(type: 0)
        }
      }
    when "subteams"
      {
        PatientTeam.school_move_location_subquery_name => {
          patient_id_source: "schlm.patient_id",
          team_id_source: "subteams.id",
          contribution_scope:
            joins(:schools).joins(join_school_moves_to_location)
        }
      }
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def update_all(updates)
    transaction do
      contributing_subqueries.each do |key, subquery|
        old_values = "temp_table_#{key}"

        rows_to_update =
          subquery[:contribution_scope].select(
            "#{table_name}.id as old_id",
            "#{subquery[:patient_id_source]} as old_patient_id",
            "#{subquery[:team_id_source]} as old_team_id"
          ).to_sql
        connection.execute <<-SQL
          CREATE TEMPORARY TABLE #{old_values} (
            old_id bigint,
            old_patient_id bigint,
            old_team_id bigint
          ) ON COMMIT DROP;
          INSERT INTO #{old_values}
          #{rows_to_update};
        SQL
      end

      super(updates)

      contributing_subqueries.each do |key, subquery|
        old_values = "temp_table_#{key}"
        update_from =
          subquery[:contribution_scope]
            .select("old_patient_id", "old_team_id")
            .joins("INNER JOIN #{old_values} ON old_id = #{table_name}.id")
            .where("old_patient_id != #{subquery[:patient_id_source]}")
            .or(where("old_team_id != #{subquery[:team_id_source]}"))
            .reorder("old_patient_id")
            .distinct
            .to_sql

        connection.execute <<-SQL
        UPDATE patient_teams pt
        SET (sources, updated_at) = (array_remove(sources, '#{key}'), CURRENT_TIMESTAMP)
        FROM (#{update_from}) AS pre_changed
        WHERE pt.patient_id = pre_changed.old_patient_id AND pt.team_id = pre_changed.old_team_id;
        SQL

        insert_from =
          subquery[:contribution_scope]
            .select(
              "#{subquery[:patient_id_source]} as patient_id",
              "#{subquery[:team_id_source]} as team_id"
            )
            .joins("INNER JOIN #{old_values} ON old_id = #{table_name}.id")
            .reorder("patient_id")
            .distinct
            .to_sql

        connection.execute <<-SQL
        INSERT INTO patient_teams (patient_id, team_id, sources)
        SELECT post_changed.patient_id, post_changed.team_id, ARRAY['#{key}']
        FROM (#{insert_from}) as post_changed
        ON CONFLICT (team_id, patient_id) DO UPDATE
        SET (sources, updated_at) = (array_append(array_remove(patient_teams.sources,'#{key}'),'#{key}'), CURRENT_TIMESTAMP)
        SQL
      end
    end
  end

  def delete_all
    transaction do
      contributing_subqueries.each do |key, subquery|
        delete_from =
          subquery[:contribution_scope]
            .select(
              "#{subquery[:patient_id_source]} as patient_id",
              "#{subquery[:team_id_source]} as team_id"
            )
            .reorder("patient_id")
            .distinct
            .to_sql

        connection.execute <<-SQL
        UPDATE patient_teams pt
        SET (sources, updated_at) = (array_remove(pt.sources, '#{key}'), CURRENT_TIMESTAMP)
        FROM (#{delete_from}) AS del
        WHERE pt.patient_id = del.patient_id AND pt.team_id = del.team_id;
        SQL
      end

      super
    end
  end

  private

  def join_vaccination_records_to_organisation
    <<-SQL
      INNER JOIN vaccination_records vacs
        ON vacs.performed_ods_code = organisations.ods_code
    SQL
  end

  def join_teams_to_vaccinations_via_organisation
    <<-SQL
      INNER JOIN organisations org
          ON vaccination_records.performed_ods_code = org.ods_code
      INNER JOIN teams tms
          ON org.id = tms.organisation_id
    SQL
  end

  def join_subteams_to_school_moves_via_location
    <<-SQL
      INNER JOIN locations loc
        ON school_moves.school_id = loc.id
      INNER JOIN subteams stm
        ON loc.subteam_id = stm.id
    SQL
  end

  def join_school_moves_to_location
    <<-SQL
      INNER JOIN school_moves schlm
        ON schlm.school_id = locations.id
    SQL
  end
end

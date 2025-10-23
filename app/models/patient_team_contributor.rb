# frozen_string_literal: true

module PatientTeamContributor
  def contributing_subqueries
    case table_name
    when "patient_locations"
      {
        PatientTeam.pls_subquery_name => {
          patient_id_source: "patient_locations.patient_id",
          team_id_source: "sessions.team_id",
          contribution_scope: joins_sessions
        }
      }
    when "archive_reasons"
      {
        PatientTeam.ars_subquery_name => {
          patient_id_source: "archive_reasons.patient_id",
          team_id_source: "archive_reasons.team_id",
          contribution_scope: all
        }
      }
    when "sessions"
      {
        PatientTeam.pls_subquery_name => {
          patient_id_source: "patient_locations.patient_id",
          team_id_source: "sessions.team_id",
          contribution_scope: joins_patient_locations
        },
        PatientTeam.vac_session_subquery_name => {
          patient_id_source: "vaccination_records.patient_id",
          team_id_source: "sessions.team_id",
          contribution_scope: joins(:vaccination_records)
        }
      }
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def source
    case table_name
    when "patient_locations"
      PatientTeam.pls_subquery_name
    when "archive_reasons"
      PatientTeam.ars_subquery_name
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def update_all(updates)
    affected_columns =
      if updates.is_a?(Hash)
        updates.keys.map(&:to_s) & tracked_column_changes
      else
        tracked_column_changes
      end
    transaction do
      contributing_subqueries.each do |key, subquery|
        old_values = "temp_table_#{key}"

        next if affected_columns.blank?
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
end

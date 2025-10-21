# frozen_string_literal: true

module PatientTeamContributor
  def patient_id_source
    case table_name
    when "patient_locations"
      "patient_locations.patient_id"
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def team_id_source
    case table_name
    when "patient_locations"
      "sessions.team_id"
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def tracked_column_changes
    case table_name
    when "patient_locations"
      %w[patient_id academic_year location_id]
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def contribution_to_patient_teams
    case table_name
    when "patient_locations"
      joins_sessions
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def source
    case table_name
    when "patient_locations"
      PatientTeam.pls_subquery_name
    else
      raise "Unknown table for PatientTeamContributor"
    end
  end

  def update_all(updates)
    transaction do
      old_values = "temp_old_pairs"

      affected_columns =
        if updates.is_a?(Hash)
          updates.keys.map(&:to_s) & tracked_column_changes
        else
          tracked_column_changes
        end

      if affected_columns.present?
        rows_to_update =
          contribution_to_patient_teams.select(
            "#{table_name}.id as old_id",
            "#{patient_id_source} as old_patient_id",
            "#{team_id_source} as old_team_id"
          )
        Rails.logger.debug "rows to update:"
        Rails.logger.debug rows_to_update.to_sql
        connection.execute <<-SQL
          CREATE TEMPORARY TABLE #{old_values} (
            old_id bigint,
            old_patient_id bigint,
            old_team_id bigint
          ) ON COMMIT DROP;
          INSERT INTO #{old_values}
          #{rows_to_update.to_sql};
        SQL
      end

      count = super(updates)

      update_from =
        contribution_to_patient_teams
          .select("old_patient_id", "old_team_id")
          .joins("INNER JOIN #{old_values} ON old_id = #{table_name}.id")
          .where("old_patient_id != #{patient_id_source}")
          .or(where("old_team_id != #{team_id_source}"))
          .distinct
          .to_sql
      Rails.logger.debug "update from:"
      Rails.logger.debug update_from
      connection.execute <<-SQL
        UPDATE patient_teams pt
        SET sources = array_remove(sources, '#{source}')
        FROM (#{update_from}) AS pre_changed
        WHERE pt.patient_id = pre_changed.old_patient_id AND pt.team_id = pre_changed.old_team_id;
      SQL

      insert_from =
        contribution_to_patient_teams
          .select(
            "#{patient_id_source} as patient_id",
            "#{team_id_source} as team_id"
          )
          .joins("INNER JOIN #{old_values} ON old_id = #{table_name}.id")
          .distinct
          .to_sql
      Rails.logger.debug "insert from:"
      Rails.logger.debug insert_from
      connection.execute <<-SQL
        INSERT INTO patient_teams (patient_id, team_id, sources, created_at)
        SELECT post_changed.patient_id, post_changed.team_id, ARRAY['#{source}'], CURRENT_TIMESTAMP
        FROM (#{insert_from}) as post_changed
        ON CONFLICT (team_id, patient_id) DO UPDATE
        SET (sources, updated_at) = (array_append(array_remove(patient_teams.sources,'#{source}'),'#{source}'), CURRENT_TIMESTAMP)
      SQL

      count
    end
  end

  def delete_all
    delete_from =
      contribution_to_patient_teams
        .select(
          "#{patient_id_source} as patient_id",
          "#{team_id_source} as team_id"
        )
        .distinct
        .to_sql

    connection.execute <<-SQL
        UPDATE patient_teams pt
        SET (sources, updated_at) = (array_remove(pt.sources, '#{source}'), CURRENT_TIMESTAMP)
        FROM (#{delete_from}) AS del
        WHERE pt.patient_id = del.patient_id AND pt.team_id = del.team_id;
    SQL
    super
  end
end

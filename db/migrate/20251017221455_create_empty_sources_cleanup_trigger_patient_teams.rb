# frozen_string_literal: true

class CreateEmptySourcesCleanupTriggerPatientTeams < ActiveRecord::Migration[
  8.0
]
  def up
    execute <<-SQL
      CREATE OR REPLACE FUNCTION cleanup_empty_sources_on_patient_teams()
      RETURNS TRIGGER AS $$
      BEGIN
        DELETE FROM patient_teams WHERE sources = ARRAY[]::text[];
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER trg_cleanup_empty_sources
        AFTER UPDATE ON patient_teams
        FOR EACH STATEMENT
        EXECUTE FUNCTION cleanup_empty_sources_on_patient_teams();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS trg_cleanup_empty_sources ON patient_teams;"
    execute "DROP FUNCTION IF EXISTS cleanup_empty_sources_on_patient_teams();"
  end
end

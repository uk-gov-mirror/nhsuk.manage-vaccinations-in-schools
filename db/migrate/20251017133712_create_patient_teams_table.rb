# frozen_string_literal: true

class CreatePatientTeamsTable < ActiveRecord::Migration[8.0]
  def up
    create_table :patient_teams, primary_key: %i[team_id patient_id] do |t|
      t.references :patient, null: false, foreign_key: { on_delete: :cascade }
      t.references :team, null: false, foreign_key: { on_delete: :cascade }
      t.text "sources", null: false, array: true
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }

      t.index %i[patient_id team_id]
      t.index %i[sources], using: :gin
    end
  end

  def down
    drop_table :patient_teams
  end
end

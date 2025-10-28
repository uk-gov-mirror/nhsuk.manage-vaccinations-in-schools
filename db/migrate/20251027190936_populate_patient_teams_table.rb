# frozen_string_literal: true

class PopulatePatientTeamsTable < ActiveRecord::Migration[8.0]
  def change
    [PatientLocation, SchoolMove, ArchiveReason, VaccinationRecord].each do
      it.all.sync_patient_teams
    end
  end
end

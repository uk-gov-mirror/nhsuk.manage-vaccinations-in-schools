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
FactoryBot.define do
  factory :patient_team, class: "PatientTeam" do
    patient
    team

    sources { [PatientTeam.patient_location_subquery_name] }

    trait :via_patient_location do
      sources { [PatientTeam.patient_location_subquery_name] }
    end

    trait :via_archive_reason do
      sources { [PatientTeam.archive_reason_subquery_name] }
    end

    trait :via_vaccination_record do
      sources { [PatientTeam.vaccination_record_session_subquery_name] }
    end

    trait :via_school_move do
      sources { [PatientTeam.school_move_subquery_name] }
    end

    trait :multiple_sources do
      sources do
        [
          PatientTeam.patient_location_subquery_name,
          PatientTeam.vaccination_record_session_subquery_name
        ]
      end
    end
  end
end

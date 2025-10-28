# frozen_string_literal: true

describe CheckPatientTeamsTableJob do
  subject(:perform) { described_class.new.perform }

  let!(:organisation) { create(:organisation) }
  let!(:team) { create(:team, organisation:) }
  let!(:programme) { create(:programme, :hpv) }
  let!(:location) { create(:school, team:) }
  let!(:session) { create(:session, team:, programmes: [programme], location:) }

  before { allow(Rails.logger).to receive(:warn) }

  context "when patient teams are correct" do
    before { create(:patient_location, session:) }

    it "logs no discrepancies" do
      perform
      expect(Rails.logger).to have_received(:warn).with(
        /Found 0 unexpected records and 0 missing records/
      )
    end
  end

  context "with unexpected patient team record" do
    before { create(:patient_team, team:) }

    it "logs unexpected records" do
      perform
      expect(Rails.logger).to have_received(:warn).with(
        /Found 1 unexpected records and 0 missing records/
      )
    end
  end

  context "with missing patient team record" do
    before do
      create(:patient_location, session:)
      PatientTeam.destroy_all
    end

    it "logs missing records" do
      perform
      expect(Rails.logger).to have_received(:warn).with(
        /Found 0 unexpected records and 1 missing records./
      )
    end
  end

  context "with multiple source types" do
    before do
      create(
        :archive_reason,
        team:,
        patient: create(:patient, school: location),
        type: :imported_in_error
      )
      create(
        :school_move,
        school: location,
        patient: create(:patient, school: location)
      )
      create(
        :vaccination_record,
        session:,
        patient: create(:patient, school: location),
        programme:,
        performed_ods_code: organisation.ods_code
      )
      create(
        :vaccination_record,
        performed_ods_code: organisation.ods_code,
        patient: create(:patient, school: location),
        programme:
      )
    end

    it "validates all sources" do
      perform
      expect(Rails.logger).to have_received(:warn).with(
        /Found 0 unexpected records and 0 missing records./
      )
    end
  end
end

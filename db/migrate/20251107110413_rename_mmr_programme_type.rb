# frozen_string_literal: true

class RenameMMRProgrammeType < ActiveRecord::Migration[8.1]
  def change
    Programme.where(type: "mmrv").update_all(type: "mmrv")
  end
end

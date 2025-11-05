# frozen_string_literal: true

class AddApprovedByUserIdToCohortImports < ActiveRecord::Migration[8.1]
  def change
    change_table :cohort_imports, bulk: true do |t|
      t.bigint :reviewed_by_user_ids, array: true, default: []
      t.datetime :reviewed_at, array: true, default: []
    end
  end
end

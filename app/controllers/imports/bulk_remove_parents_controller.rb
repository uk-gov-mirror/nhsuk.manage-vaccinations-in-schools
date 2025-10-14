# frozen_string_literal: true

module Imports
  class BulkRemoveParentsController < ApplicationController
    before_action :set_import
    skip_after_action :verify_policy_scoped

    def show
    end

    def create
      if params[:remove_option] == "unconsented"
        @import.destroy_parents_without_consent!
      else
        @import.destroy_parents!
      end

      redirect_to imports_path, notice: "Parents removed successfully."
    end

    private

    def set_import
      import_class = params[:import_type].classify.safe_constantize
      @import = import_class&.find(params[:import_id])
      raise ActiveRecord::RecordNotFound unless @import
    end
  end
end

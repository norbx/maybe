class ChartsController < ApplicationController
  include Periodable

  def index
    @balance_sheet = Current.family.balance_sheet
    @current_category_id = params[:current_category_id] || Current.family.categories.last.id
  end
end

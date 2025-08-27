class ChartsController < ApplicationController
  include Periodable

  def index
    @balance_sheet = Current.family.balance_sheet
  end
end

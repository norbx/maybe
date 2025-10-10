class PricesController < ApplicationController
  include StreamExtensions

  def new
    @account = Current.family.accounts.find(params[:account_id])
    @model = Security::Price.new
  end

  def create
    @account = Current.family.accounts.find(params[:account_id])
    @model = Security::Price.new(create_params)

    if @model.save
      flash[:notice] = t("prices.create.success")

      respond_to do |format|
        format.html { redirect_back_or_to account_path(@account) }
        format.turbo_stream { stream_redirect_back_or_to account_path(@account) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

    def create_params
      params.require(:model).permit(:security_id, :date, :price, :currency)
    end
end

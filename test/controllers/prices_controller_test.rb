require "test_helper"

class PricesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @family = families(:empty)
    sign_in @user = users(:empty)
  end

  test "creates with price details" do
    @account = @family.accounts.create!(
      name: "Test Account",
      balance: 0,
      currency: "USD",
      accountable: Investment.new,
      holdings: [holdings(:one)]
    )
    @holding = @account.holdings.first

    @holding.security.prices.delete_all

    assert_difference "Security::Price.count", 1 do
      post prices_url, params: {
        account_id: @account.id,
        model: {
          security_id: @holding.security_id,
          date: Date.current,
          price: 150.0,
          currency: "USD"
        }
      }
    end
  end
end

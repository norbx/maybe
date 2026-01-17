require "test_helper"

class TransactionImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper, ImportInterfaceTest

  setup do
    @subject = @import = imports(:transaction)
  end

  test "uploaded? if raw_file_str is present" do
    @import.expects(:raw_file_str).returns("test").once
    assert @import.uploaded?
  end

  test "configured? if uploaded and rows are generated" do
    @import.expects(:uploaded?).returns(true).once
    assert @import.configured?
  end

  test "cleaned? if rows are generated and valid" do
    @import.expects(:configured?).returns(true).once
    assert @import.cleaned?
  end

  test "publishable? if cleaned and mappings are valid" do
    @import.expects(:cleaned?).returns(true).once
    assert @import.publishable?
  end

  test "imports transactions, categories, tags, and accounts" do
    import = <<~CSV
      date,name,amount,category,tags,account,notes
      01/01/2024,Txn1,100,TestCategory1,TestTag1,TestAccount1,notes1
      01/02/2024,Txn2,200,TestCategory2,TestTag1|TestTag2,TestAccount2,notes2
      01/03/2024,Txn3,300,,,,notes3
    CSV

    @import.update!(
      raw_file_str: import,
      date_col_label: "date",
      amount_col_label: "amount",
      date_format: "%m/%d/%Y"
    )

    @import.generate_rows_from_csv

    @import.mappings.create! key: "TestCategory1", create_when_empty: true, type: "Import::CategoryMapping"
    @import.mappings.create! key: "TestCategory2", mappable: categories(:food_and_drink), type: "Import::CategoryMapping"
    @import.mappings.create! key: "", create_when_empty: false, mappable: nil, type: "Import::CategoryMapping" # Leaves uncategorized

    @import.mappings.create! key: "TestTag1", create_when_empty: true, type: "Import::TagMapping"
    @import.mappings.create! key: "TestTag2", mappable: tags(:one), type: "Import::TagMapping"
    @import.mappings.create! key: "", create_when_empty: false, mappable: nil, type: "Import::TagMapping" # Leaves untagged

    @import.mappings.create! key: "TestAccount1", create_when_empty: true, type: "Import::AccountMapping"
    @import.mappings.create! key: "TestAccount2", mappable: accounts(:depository), type: "Import::AccountMapping"
    @import.mappings.create! key: "", mappable: accounts(:depository), type: "Import::AccountMapping"

    @import.reload

    assert_difference -> { Entry.count } => 3,
                      -> { Transaction.count } => 3,
                      -> { Tag.count } => 1,
                      -> { Category.count } => 1,
                      -> { Account.count } => 1 do
      @import.publish
    end

    assert_equal "complete", @import.status
  end

  test "imports transactions with separate type column for signage convention" do
    import = <<~CSV
      date,amount,amount_type
      01/01/2024,100,debit
      01/02/2024,200,credit
      01/03/2024,300,debit
    CSV

    @import.update!(
      account: accounts(:depository),
      raw_file_str: import,
      date_col_label: "date",
      date_format: "%m/%d/%Y",
      amount_col_label: "amount",
      entity_type_col_label: "amount_type",
      amount_type_inflow_value: "debit",
      amount_type_strategy: "custom_column",
      signage_convention: nil # Explicitly set to nil to prove this is not needed
    )

    @import.generate_rows_from_csv

    @import.reload

    assert_difference -> { Entry.count } => 3,
                      -> { Transaction.count } => 3 do
      @import.publish
    end

    assert_equal [-100, 200, -300], @import.entries.map(&:amount)
  end

  test "imports transactions with specific bank data format" do
    import = <<~CSV
      This is some random text that my bank
      puts before the actual transaction data.

      There are often blank lines
      # and the ones that start with some arbitrarty characters.

      Also note that the data format differs and needs to be cleaned
      before importing.

      #Data operacji;#Opis operacji;#Rachunek;#Kategoria;#Kwota;
      2025-12-28;"Żabka  ZAKUP PRZY UŻYCIU KARTY W KRAJU transakcja nierozliczona";"mKonto Intensive 6311 ... 0016";"Żywność i chemia domowa";-7,57 PLN;;
      2025-12-27;"Trattoria Numero Uno  ZAKUP PRZY UŻYCIU KARTY W KRAJU transakcja nierozliczona";"mKonto Intensive 6311 ... 0016";"Jedzenie poza domem";-61,00 PLN;;
    CSV

    @import.update!(
      account: accounts(:depository),
      raw_file_str: import,
      col_sep: ";",
      date_col_label: "#Data operacji",
      date_format: "%Y-%m-%d",
      amount_col_label: "#Kwota",
      name_col_label: "#Opis operacji",
      category_col_label: "#Kategoria",
    )

    @import.generate_rows_from_csv

    @import.reload

    assert_difference -> { Entry.count } => 2,
                      -> { Transaction.count } => 2 do
      @import.publish
    end

    assert_equal [-100, -200], @import.entries.map(&:amount)
  end
end

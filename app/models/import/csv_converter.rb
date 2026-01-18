module Import::CsvConverter
  CSV_HEADER_PATTERNS = {
    "mbank" => [/^#Data operacji/, /^#Opis operacji/, /^#Rachunek/, /^#Kategoria/, /^#Kwota/]
  }

  def parse_csv_str(csv_str, col_sep: ",")
    csv_str = (csv_str || "").strip

    header_index = find_header_index(csv_str, col_sep: col_sep)

    normalized_csv_str = if header_index.zero?
      csv_str
    else
      lines = csv_str.split("\n")
      lines[header_index..].join("\n")
    end

    CSV.parse(
      normalized_csv_str,
      headers: true,
      col_sep: col_sep,
      converters: [->(str) { str&.strip }, amount_converter],
      liberal_parsing: true
    )
  end

    private

      def find_header_index(csv_str, col_sep: ",")
        lines = csv_str.split("\n")

        lines.each_with_index do |line, index|
          CSV_HEADER_PATTERNS.each do |_, patterns|
            begin
              cells = CSV.parse_line(line, col_sep: col_sep)
              next if cells.nil? || cells.empty?

              matches = cells.count do |cell|
                next false if cell.nil?
                patterns.any? { |pattern| cell.match?(pattern) }
              end

              return index if matches >= 2
            rescue CSV::MalformedCSVError
              next
            end
          end
        end
        0
      end

      def amount_converter
        lambda do |str, field_metadata|
          if field_metadata.header&.match?(/#Kwota/)
            str&.gsub(/\s*[A-Z]{3}\s*$/, "")&.gsub(",", ".")
          else
            str
          end
        end
      end
end

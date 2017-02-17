class OrderInformation
  attr_accessor :name, :phone_number

  def input
    response = Request.get("https://order.dominos.jp/eng/receipt/input/",
                           expect: :ok, failure: "Couldn't get information input page")

    saved_name = Name.from(response.body)
    phone_numbers = PhoneNumbers.from(response.body)

    self.name = Ask.input "Name", default: saved_name
    phone_number_index = Ask.list "Phone Number", phone_numbers.selection_list
    self.phone_number = phone_numbers[phone_number_index]

    @first_response = response
  end

  def validate
    raise "Missing attributes" unless name && phone_number

    # Get the default parameters and add in the client name and phone number
    params = default_params.merge(
      "kokyakuNm" => name,
      "telSeq" => phone_number.value
    )

    @second_response = Request.post("https://order.dominos.jp/eng/receipt/confirm", params,
                                    expect: :ok, failure: "Couldn't set your information") do |resp|
      resp.body.include?("Order Type, Day&Time and Your Store")
    end
  end

  def display
    doc = Nokogiri::HTML(@second_response.body)
    info = doc.css(".m-input__heading").map(&:text).
               zip(doc.css(".section_content_table_td").map(&:text)).to_h
    @page_params = doc.css("input[type=hidden]").map do |input|
      [input["name"], input["value"]]
    end.to_h

    info.each { |title, value| puts "#{title.colorize(:blue)}: #{value}" }
  end

  def confirm
    raise "Stopped by user" unless (Ask.confirm "Continue?")

    Request.post("https://order.dominos.jp/eng/receipt/complete", @page_params,
                 expect: :redirect, to: "https://order.dominos.jp/eng/menu/",
                 failure: "Couldn't validate your information")
  end

  private

  def default_params
    kokyaku_input = Nokogiri::HTML(@first_response.body).css("input[name=kokyakuC]").first
    raise "Couldn't find client information" unless kokyaku_input

    {
      "kokyakuC" => kokyaku_input["value"],
      # Rest is untouched
      "errorMessage" => "",
      "receiptMethod" => "1", # Receipt method again...
      "deleteTelSeq" => "",
      "telNoRadio" => "0",
      "telNo" => ""
    }
  end
end

class Name
  def self.from(source)
    doc = Nokogiri::HTML(source)
    input = doc.css("input[name=kokyakuNm]").first
    raise "Couldn't get name field from information input page" unless input

    input["value"]
  end
end

class PhoneNumbers < Array
  def self.from(source)
    doc = Nokogiri::HTML(source)
    numbers = doc.css("select[name=telSeq] > option").map { |option| PhoneNumber.new(option) }

    unless numbers.size > 0
      raise "Couldn't find any saved phone numbers in the information input page"
    end

    PhoneNumbers.new(numbers)
  end

  def selection_list
    map(&:list_item)
  end
end

class PhoneNumber
  attr_accessor :number, :value

  def initialize(option)
    self.number = option.text
    self.value = option["value"]
  end

  def list_item
    number
  end
end

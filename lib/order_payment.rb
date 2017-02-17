require "credit_card_validations"
require "credit_card_validations/string"

class OrderPayment
  attr_accessor :default_name
  attr_accessor :note
  attr_accessor :last_review
  attr_accessor :page

  def input
    Request.get("https://order.dominos.jp/eng/regi/",
                expect: :ok, failure: "Couldn't get payment page")

    puts
    puts
    puts "#{"Payment information".colorize(:blue)} (you will be able to review your order later)"

    @credit_card = CreditCard.new
    @credit_card.input(default_name)

    self.note = Ask.input "Any special requests? (not food preparation requests)"
  end

  def validate
    params = default_params.merge("bikoText" => note).merge(@credit_card.params)
    response = Request.post("https://order.dominos.jp/eng/regi/confirm", params,
                            expect: :ok, failure: "Couldn't submit payment information")
    doc = Nokogiri::HTML(response.body)

    token_input = doc.css("input[name='org.apache.struts.taglib.html.TOKEN']").first
    raise "Couldn't get token for order validation" unless token_input && token_input["value"]

    @insert_params = doc.css("input").map { |input| [input["name"], input["value"]] }.to_h

    self.last_review = OrderLastReview.new(doc)
    self.page = response.body
  end

  def display
    puts last_review
  end

  def confirm
    puts

    unless Ask.confirm "Place order?"
      puts "Stopped by user"
      return
    end

    Request.post("https://order.dominos.jp/eng/regi/insert", @insert_params,
                 expect: :redirect, to: %r{\Ahttps://order\.dominos\.jp/eng/regi/complete/\?},
                 failure: "Order couldn't be placed for some reason :(")

    puts
    puts "Success!"
    puts "Be sure to check the Domino's website in your browser "\
         "to track your order status, and win a coupon"
  end

  private

  def default_params
    {
      "inquiryRiyoDStr" => "undefined",
      "inquiryCardComCd" => "undefined",
      "inquiryCardBrand" => "undefined",
      "inquiryCreditCardNoXXX" => "undefined",
      "inquiryGoodThruMonth" => "undefined",
      "inquiryGoodThruYear" => "undefined",
      "creditCard" => "undefined",
      "receiptK" => "0",
      "exteriorPayment" => "4",
      "reuseCreditDiv" => "1",
      "rakutenPayment" => "1",
      "isDisplayMailmagaArea" => "true",
      "isProvisionalKokyakuModalView" => "false",
      "isProvisionalKokyaku" => "false"
    }
  end
end

class OrderLastReview
  attr_accessor :doc

  def initialize(doc)
    self.doc = doc
  end

  def to_s
    sections = doc.css(".l-section").map do |section|
      next unless section.css(".m-heading__caption").count > 0

      section_name = section.css(".m-heading__caption").text.strip.gsub(/\s+/, " ").colorize(:green)
      rows = section.css("tr").map do |row|
        th = row.css(".m-input__heading").first || row.css("th").first
        th_text = th.text.strip.gsub(/\s+/, " ").colorize(:blue)
        td_text = row.css(".section_content_table_td").text.
                      gsub(/ +/, " ").gsub(/\t+/, "").gsub(/(?:\r\n)+/, "\r\n").strip

        "#{th_text}\n#{td_text}"
      end

      "\n#{section_name}\n#{rows.join("\n")}"
    end

    sections.join("\n")
  end
end

class CreditCard
  VALUES = {
    visa: "00200",
    mastercard: "00300",
    jcb: "00500",
    amex: "00400",
    diners: "00100",
    nicos: "00600"
  }

  def input(default_name = nil)
    loop do
      credit_card_number = ""
      while !credit_card_number.valid_credit_card_brand?(:visa, :mastercard, :jcb, :amex, :diners)
        puts "Invalid card number" unless credit_card_number == ""
        credit_card_number = Ask.input "Credit Card Number"
      end

      unless credit_card_number.credit_card_brand == :diners
        cvv = Ask.input "CVV"
      end

      expiration_month, expiration_year = ""
      loop do
        expiration_date = Ask.input "Expiration Date (mm/yy)"
        expiration_month, expiration_year = expiration_date.split("/")
        break if (1..12).include?(expiration_month.to_i) && (17..31).include?(expiration_year.to_i)
      end

      name = Ask.input "Name on Card", default: default_name

      @params = {
        "existCreditCardF" => "",
        "reuseCredit_check" => "1", # Seems to be 1 but it doesn't save the CC info
        "cardComCd" => VALUES[credit_card_number.credit_card_brand],
        "creditCardNo" => credit_card_number,
        "creditCardSecurityCode" => cvv,
        "creditCardSignature" => name,
        "goodThruMonth" => expiration_month.rjust(2, "0"),
        "goodThruYear" => expiration_year
      }

      break if valid?
    end
  end

  def params
    @params
  end

  def valid?
    response = Request.post(
      "https://order.dominos.jp/eng/webapi/regi/validate/creditCard/", @params,
      expect: :ok, failure: "Couldn't validate credit card info"
    )

    result = JSON.parse(response.body)
    if result["errorDetails"]
      puts result
      return false
    end

    true
  end
end

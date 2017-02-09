require "inquirer"
require "highline"
require "net/https"
require "nokogiri"
require "http-cookie"
require "colorize"
require "credit_card_validations"
require "credit_card_validations/string"
require "byebug"
require_relative "lib/request"

@total_price = 0
@total_price_without_tax = 0
@name = nil

def login(email, password)
  Request.post(
    "https://order.dominos.jp/eng/login/login/", { "emailAccount" => email, "webPwd" => password },
    expect: :redirect, failure: "Couldn't log in successfully"
  )
end

def order_type
  response = Request.get("https://order.dominos.jp/eng/receipt/",
                         expect: :ok, failure: "Couldn't get order types page")

  doc = Nokogiri::HTML(response.body)
  addresses = doc.css(".l-section.m-addressSelect .addressSelect_content").map do |address_content|
    {
      label: address_content.css(".addressSelect_labelName").text.strip,
      address: address_content.css(".addressSelect_information_address").text.strip,
      estimation: address_content.css(".time_content_text").text.strip,
      id: address_content.css("input[name=todokeSeq]").first["value"].strip
    }
  end

  index = Ask.list "Choose an address", (addresses.map do |a|
    a.values_at(:label, :address, :estimation).join("\n    ")
  end)

  address = addresses[index]

  params = {
    "tenpoC" => "", "jushoC" => "", "kokyakuJushoBanchi" => "", "banchiCheckBox" => "", "buildNm" => "",
    "buildCheckBox" => "", "todokeShortNm" => "", "kigyoNm" => "", "bushoNm" => "", "naisen" => "",
    "targetYmd" => nil, "targetYmdhm" => nil, "gpsPinpointF" => false
  }
  params["receiptMethod"] = "1" # 1=delivery, 3=pickup
  params["todokeSeq"] = address[:id] # Set the delivery address

  Request.post("https://order.dominos.jp/eng/receipt/setReceipt", params,
               expect: :redirect, to: "https://order.dominos.jp/eng/receipt/input/",
               failure: "Couldn't set the delivery address")
end

def input
  response = Request.get("https://order.dominos.jp/eng/receipt/input/",
                         expect: :ok, failure: "Couldn't get information input page")

  doc = Nokogiri::HTML(response.body)
  name_input = doc.css("input[name=kokyakuNm]").first
  phone_numbers = doc.css("select[name=telSeq] > option").map { |option| [option.text, option["value"]] }.to_h

  unless name_input
    puts "Couldn't get name field from information input page"
    return
  end

  unless phone_numbers.size > 0
    puts "Couldn't find any saved phone numbers in the information input page"
    return
  end

  @name = Ask.input "Name", default: name_input["value"]
  phone_number_index = Ask.list "Phone number", phone_numbers.map(&:first)
  phone_number_value = phone_numbers[phone_numbers.map(&:first)[phone_number_index]]

  params = { "errorMessage" => "", "receiptMethod" => "1", "deleteTelSeq" => "",
             "telNoRadio" => "0", "telNo" => "" }
  params["kokyakuC"] = doc.css("input[name=kokyakuC]").first["value"]
  params["kokyakuNm"] = @name
  params["telSeq"] = phone_number_value

  response = Request.post("https://order.dominos.jp/eng/receipt/confirm", params,
                          expect: :ok, failure: "Couldn't set your information") do |resp|
    resp.body.include?("Order Type, Day&Time and Your Store")
  end

  doc = Nokogiri::HTML(response.body)
  info = doc.css(".m-input__heading").map(&:text).zip(doc.css(".section_content_table_td").map(&:text)).to_h
  params = doc.css("input[type=hidden]").map { |input| [input["name"], input["value"]] }.to_h

  info.each do |title, value|
    puts "#{title.colorize(:blue)}: #{value}"
  end

  value = Ask.confirm "Continue?"

  unless value
    puts "Stopped by user"
    return
  end

  Request.post("https://order.dominos.jp/eng/receipt/complete", params
               expect: :redirect, to: "https://order.dominos.jp/eng/menu/",
               failure: "Couldn't validate your information")
end

def select_pizzas
  response = Request.get("https://order.dominos.jp/eng/pizza/search/",
                         expect: :ok, failure: "Couldn't get pizza list page")

  doc = Nokogiri::HTML(response.body)
  pizza_options = doc.css(".jso-dataLayerProductClick").map do |anchor_element|
    next unless anchor_element["iname"]

    link = anchor_element["href"]
    parts = link.split("/")
    pizza_id = parts.pop
    category_id = parts.pop
    # some_other_number = parts.pop # TODO: figure out what this is

    description = anchor_element.css(".menu_itemList_item_text").first
    description = description.text if description

    allergen_warning = anchor_element.css(".js-menuSetHeight_allergen").first
    allergen_warning = allergen_warning.text if allergen_warning

    {
      url: "https://order.dominos.jp#{link}",
      shohinC1: pizza_id,
      categoryC: category_id,
      name: anchor_element["iname"],
      description: description,
      allergen_warning: allergen_warning
    }
  end.compact

  cli = HighLine.new
  multiple_pizza = false
  choices = pizza_options.map do |pizza_option|
    name, description, allergen_warning = pizza_option.values_at(
      :name, :description, :allergen_warning
    )
    allergen_warning ||= ""

    "#{name.colorize(:blue)} #{allergen_warning.strip.colorize(:yellow)}\n"\
    "  #{description.gsub(',', ', ').gsub(')', ') ')}\n"\
  end

  loop do
    cli.choose do |menu|
      menu.prompt = "Add a#{"nother" if multiple_pizza} pizza:"
      menu.choices(*choices) do |choice|
        return if choice == "Enough!" && multiple_pizza

        if choice != "Enough!"
          selected_pizza = pizza_options[choices.index(choice)]
          customized_pizza = customize_pizza(selected_pizza)
          exit unless add_pizza(customized_pizza)
        end
      end
      menu.default = "Enough!"
    end

    unless multiple_pizza
      choices.push("Enough!")
      multiple_pizza = true
    end
  end
end

def customize_pizza(pizza)
  response = Request.get(pizza[:url], expect: :ok, failure: "Couldn't open pizza detail page")
  doc = Nokogiri::HTML(response.body)

  puts pizza[:name].colorize(:blue)

  # TODO: Allow toppings selection

  # Choosing the size
  size_options = doc.css("#detail_selectSize .m-input__radio").map do |size_option|
    {
      text: size_option.text,
      value: size_option.css("input[name=sizeC]").first["value"]
    }
  end

  size_choices = size_options.map do |choice|
    choice[:text].gsub(/\s+/, " ").sub("人 /", "人/").sub("cm ", "cm\n  ").sub(" ¥", "\n  ¥").strip
  end

  selected_size_index = Ask.list "Choose the size", size_choices
  selected_size = size_options[selected_size_index]

  # Choosing the crust
  crust_options = doc.css("#detail_selectCrust .m-input__radio").map do |crust_option|
    {
      text: crust_option.css(".caption_radio").first.text,
      value: crust_option.css("input[name=crustC]").first["value"]
    }
  end

  crust_choices = crust_options.map do |choice|
    choice[:text].gsub(/\s+/, " ").strip
  end

  selected_crust_index = Ask.list "Choose the crust", crust_choices
  selected_crust = crust_options[selected_crust_index]

  pizza["sizeC"] = selected_size[:value]
  pizza["crustC"] = selected_crust[:value]

  # TODO: Allow cut type, number of slices, quantity selection
  pizza["cutTypeC"] = 1 # Type of cut: 1=Round Cut
  pizza["cutSu"] = 8 # Number of slices
  pizza["figure"] = 1  # Quantity

  pizza
end

def add_pizza(preferences)
  params = { "pageId" => "PIZZA_DETAIL" }.merge(preferences)
  response = Request.post(
    "https://order.dominos.jp/eng/cart/add/pizza/", params,
    expect: :redirect, to: %r{\Ahttps?://order\.dominos\.jp/eng/cart/added/\z},
    failure: "Couldn't add the pizza you selected"
  )

  # For some reason we need to GET this URL otherwise it doesn't count as added <_<
  Request.get(response["Location"],
              expect: :redirect, to: "https://order.dominos.jp/eng/cart/",
              failure: "Couldn't add the pizza you selected")
end

def show_order_details(body = nil)
  unless body
    response = Request.get("https://order.dominos.jp/eng/pizza/search/",
                           expect: :ok, failure: "Couldn't get pizza list page")
  end

  puts
  puts
  puts "Review Your Order".colorize(:red)

  doc = Nokogiri::HTML(body || response.body)

  # Order items
  doc.css(".m-side_orderItems li").each do |order_item|
    name = order_item.css(".orderItems_item_name").first.text.strip.gsub(/\s+/, " ")
    # TODO: Get toppings list and display it

    details_element = order_item.css(".orderItems_item_detail")
    details_dt = details_element.css("dt").map { |t| t.text.strip.gsub(/\s+/, " ") }
    details_dd = details_element.css("dd").map { |t| t.text.strip.gsub(/\s+/, " ") }
    details = details_dt.zip(details_dd).to_h
    details["Price"] = order_item.css(".orderItems_item_price").text.strip.gsub(/\s+/, " ")

    puts
    puts name.colorize(:blue)
    details.each do |key, value|
      puts "  #{key}: #{value}"
    end
  end

  # Coupons
  coupon_items = doc.css(".m-side_useCoupon li")
  puts "\nCoupons".colorize(:green) if coupon_items.count > 0

  coupon_items.each do |coupon_item|
    name = coupon_item.css(".useCoupon_coupons_name").text.strip.gsub(/\s+/, " ").sub("\\", "¥")
    value = coupon_item.css("dd span").text.strip

    puts "  #{name} #{value.colorize(:green)}"
  end

  # General information
  total_price_element = doc.css(".totalPrice_taxin")
  total_price_title = total_price_element.css("dt").text.strip.gsub(/\s+/, " ")
  total_price_string = total_price_element.css("dd").text.strip.gsub(/\s+/, " ")
  @total_price = total_price_string.gsub(",", "").scan(/¥(\d+)/).flatten.first.to_i
  @total_price_without_tax = @total_price / 108 * 100 # 8% tax

  puts
  puts "#{total_price_title}: #{total_price_string.colorize(:red)}"
  puts doc.css(".totalPrice_tax").text
end

def select_coupon
  value = Ask.confirm "Add a coupon?"
  return unless value

  response = Request.get("https://order.dominos.jp/eng/coupon/use/",
                         expect: :ok, failure: "Couldn't get coupons list")

  doc = Nokogiri::HTML(response.body)
  coupons = doc.css("li").map do |item|
    name_element_text = item.css("h4").text
    coupon_name = name_element_text.sub("\\", "¥").sub("Expires soon", "")
    expires_soon = name_element_text.include?("Expires soon") ? "Expires soon" : ""

    coupon_link = item.css(".jso-userCuponUse").first || {}

    yen_value = coupon_name.scan(/¥(\d+)/).flatten.first.to_i
    percent_value = coupon_name.scan(/(\d+)%/).flatten.first.to_i

    if yen_value != 0
      real_value = yen_value * 1.08 # 8% tax
    elsif percent_value != 0
      real_value = (@total_price_without_tax / (100 / percent_value)) * 1.08 # 8% tax
    end

    error = item.css(".m-input__error").text
    error = error && error.strip != "" ? "\n    #{error}" : nil

    {
      name: coupon_name,
      expiry: item.css(".m-entryPeriod").text.scan(/\d{4}-\d{2}-\d{2}/).first,
      error: error,
      couponcd: coupon_link["couponcd"],
      couponseq: coupon_link["couponseq"],
      expires_soon: expires_soon,
      real_value: real_value.to_i
    }
  end

  coupons = [
    coupons.reject { |c| c[:error] },
    coupons.select { |c| c[:error] }
  ].map do |coups|
    coups.group_by { |coupon| coupon[:real_value] }.sort.reverse.map do |real_value, same_value_coupons|
      same_value_coupons.sort_by { |coupon| coupon[:expiry] }
    end
  end.flatten

  index = Ask.list "Choose a coupon", (coupons.map do |c|
    "#{c[:name].colorize(:blue)} (-¥#{c[:real_value].to_s.colorize(:green)}) "\
    "#{c[:expires_soon].colorize(:yellow)} #{c[:expiry]} #{c[:error].to_s.colorize(:red)}"
  end)

  coupon = coupons[index]
  params = coupon.select { |k,_| [:couponcd, :couponseq].include?(k) }

  if params.empty?
    puts "This coupon cannot be used."
    return
  end

  Request.post("https://order.dominos.jp/eng/webapi/sides/setUserCoupon/", params,
               expect: :ok, failure: "Couldn't add coupon")
end

def payment
  response = Request.get("https://order.dominos.jp/eng/regi/",
                         expect: :ok, failure: "Couldn't get payment page")

  puts
  puts
  puts "#{"Payment information".colorize(:blue)} (you will be able to review your order later)"

  credit_card_values = {
    visa: "00200",
    mastercard: "00300",
    jcb: "00500",
    amex: "00400",
    diners: "00100",
    nicos: "00600"
  }

  credit_card_params = {}
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

    name = Ask.input "Name on Card", default: @name

    credit_card_params = {
      "existCreditCardF" => "",
      "reuseCredit_check" => "1", # Seems to be 1 but it doesn't save the CC info
      "cardComCd" => credit_card_values[credit_card_number.credit_card_brand],
      "creditCardNo" => credit_card_number,
      "creditCardSecurityCode" => cvv,
      "creditCardSignature" => name,
      "goodThruMonth" => expiration_month.rjust(2, "0"),
      "goodThruYear" => expiration_year
    }

    break if validate_credit_card(credit_card_params)
  end

  note = Ask.input "Any special requests? (not food preparation requests)"

  order_params = {
    "inquiryRiyoDStr" => "undefined",
    "inquiryCardComCd" => "undefined",
    "inquiryCardBrand" => "undefined",
    "inquiryCreditCardNoXXX" => "undefined",
    "inquiryGoodThruMonth" => "undefined",
    "inquiryGoodThruYear" => "undefined",
    "creditCard" => "undefined",
    "bikoText" => note,
    "receiptK" => "0",
    "exteriorPayment" => "4",
    "reuseCreditDiv" => "1",
    "rakutenPayment" => "1",
    "isDisplayMailmagaArea" => "true",
    "isProvisionalKokyakuModalView" => "false",
    "isProvisionalKokyaku" => "false"
  }.merge(credit_card_params)

  response = Request.post("https://order.dominos.jp/eng/regi/confirm", order_params,
                          expect: :ok, failure: "Couldn't submit payment information")

  doc = Nokogiri::HTML(response.body)
  token_input = doc.css("input[name='org.apache.struts.taglib.html.TOKEN']").first
  unless token_input && token_input["value"]
    puts "Couldn't get token for order validation"
    return
  end

  insert_params = doc.css("input").map { |input| [input["name"], input["value"]] }.to_h

  puts
  doc.css(".l-section").each do |section|
    next unless section.css(".m-heading__caption").count > 0

    puts
    puts section.css(".m-heading__caption").text.strip.gsub(/\s+/, " ").colorize(:green)
    section.css("tr").each do |row|
      th = row.css(".m-input__heading").first || row.css("th").first
      puts th.text.strip.gsub(/\s+/, " ").colorize(:blue)
      puts row.css(".section_content_table_td").
               text.gsub(/ +/, " ").gsub(/\t+/, "").gsub(/(?:\r\n)+/, "\r\n").strip
    end
  end

  show_order_details(response.body)

  puts
  value = Ask.confirm "Place order?"

  unless value
    puts "Stopped by user"
    return
  end

  Request.post("https://order.dominos.jp/eng/regi/insert", insert_params,
               expect: :redirect, to: %r{\Ahttps://order\.dominos\.jp/eng/regi/complete/\?},
               failure: "Order couldn't be placed for some reason :(")

  puts
  puts "Success!"
  puts "Be sure to check the Domino's website in your browser "\
       "to track your order status, and win a coupon"
end

def validate_credit_card(params)
  response = Request.post("https://order.dominos.jp/eng/webapi/regi/validate/creditCard/", params,
                          expect: :ok, failure: "Couldn't validate credit card info")

  result = JSON.parse(response.body)
  if result["errorDetails"]
    puts result
    return
  end

  true
end

login("<email>", "<password>")
order_type
input
select_pizzas
show_order_details
select_coupon
show_order_details
payment

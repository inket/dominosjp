class OrderAddress
  attr_accessor :address

  def input
    response = Request.get("https://order.dominos.jp/eng/receipt/",
                           expect: :ok, failure: "Couldn't get order types page")

    addresses = Addresses.from(response.body)
    index = Ask.list "Choose an address", addresses.selection_list
    self.address = addresses[index]
  end

  def validate
    raise "Missing attributes" unless address

    # Get the default parameters and add in the delivery address
    params = default_params.merge("todokeSeq" => address.id)

    Request.post("https://order.dominos.jp/eng/receipt/setReceipt", params,
                 expect: :redirect, to: "https://order.dominos.jp/eng/receipt/input/",
                 failure: "Couldn't set the delivery address")
  end

  private

  def default_params
    {
      # Receipt method: 1=delivery, 3=pickup
      "receiptMethod" => "1",
      # Rest is untouched
      "tenpoC" => "",
      "jushoC" => "",
      "kokyakuJushoBanchi" => "",
      "banchiCheckBox" => "",
      "buildNm" => "",
      "buildCheckBox" => "",
      "todokeShortNm" => "",
      "kigyoNm" => "",
      "bushoNm" => "",
      "naisen" => "",
      "targetYmd" => nil,
      "targetYmdhm" => nil,
      "gpsPinpointF" => false
    }
  end
end

class Addresses < Array
  def self.from(source)
    doc = Nokogiri::HTML(source)

    Addresses.new(
      doc.css(".l-section.m-addressSelect .addressSelect_content").map { |el| Address.new(el) }
    )
  end

  def selection_list
    map(&:list_item)
  end
end

class Address
  attr_accessor :id, :label, :address, :estimation

  def initialize(element)
    self.label = element.css(".addressSelect_labelName").text.strip
    self.address = element.css(".addressSelect_information_address").text.strip
    self.estimation = element.css(".time_content_text").text.strip
    self.id = element.css("input[name=todokeSeq]").first["value"].strip
  end

  def list_item
    [label, address, estimation].join("\n    ")
  end
end

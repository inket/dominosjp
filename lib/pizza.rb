class Pizzas < Array
  def self.from(source)
    doc = Nokogiri::HTML(source)

    Pizzas.new(
      doc.css(".jso-dataLayerProductClick").map { |el| Pizza.new(el) }.select(&:valid?)
    )
  end

  def selection_list
    map(&:list_item)
  end
end

class Pizza
  attr_accessor :id, :category_id, :url, :name, :description, :allergen_warning
  attr_accessor :size, :crust

  def initialize(element)
    return unless element["iname"]

    link = element["href"]
    parts = link.split("/")
    pizza_id = parts.pop
    category_id = parts.pop
    # some_other_number = parts.pop # TODO: figure out what this is

    description = element.css(".menu_itemList_item_text").first
    description = description.text if description

    allergen_warning = element.css(".js-menuSetHeight_allergen").first
    allergen_warning = allergen_warning.text if allergen_warning

    self.url = "https://order.dominos.jp#{link}"
    self.id = pizza_id # shohinC1
    self.category_id = category_id # categoryC
    self.name = element["iname"]
    self.description = description
    self.allergen_warning = allergen_warning
  end

  def valid?
    url != nil
  end

  def available_sizes
    @available_sizes ||=
      detail_page_content.css("#detail_selectSize .m-input__radio").map do |option|
        Pizza::Size.new(option)
      end
  end

  def available_crusts
    @available_crusts ||=
      detail_page_content.css("#detail_selectCrust .m-input__radio").map do |option|
        Pizza::Crust.new(option)
      end
  end

  def params
    {
      "shohinC1" => id,
      "categoryC" => category_id,
      "sizeC" => size.value,
      "crustC" => crust.value
    }
  end

  def list_item
    allergen = allergen_warning || ""

    "#{name.colorize(:blue)} "\
    "#{allergen.strip.colorize(:yellow)}\n  "\
    "#{description.gsub(',', ', ').gsub(')', ') ')}\n"
  end

  private

  def detail_page_content
    @detail_page_content ||= Nokogiri::HTML(
      Request.get(url, expect: :ok, failure: "Couldn't open pizza detail page").body
    )
  end
end

class Pizza::Size
  attr_accessor :text, :value

  def initialize(option)
    self.text = option.text.strip
    self.value = option.css("input[name=sizeC]").first["value"]
  end

  def list_item
    text.gsub(/\s+/, " ").sub("人 /", "人/").sub("cm ", "cm\n  ").sub(" ¥", "\n  ¥").strip
  end
end

class Pizza::Crust
  attr_accessor :text, :value

  def initialize(option)
    self.text = option.css(".caption_radio").first.text.strip
    self.value = option.css("input[name=crustC]").first["value"]
  end

  def list_item
    text.gsub(/\s+/, " ").strip
  end
end

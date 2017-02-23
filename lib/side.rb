# frozen_string_literal: true
require "byebug"
class Sides < Array
  def self.from(source)
    doc = Nokogiri::HTML(source)

    Sides.new(
      doc.css(".jso-dataLayerProductClick").map { |el| Side.new(el) }.select(&:valid?)
    )
  end

  def selection_list
    map(&:list_item)
  end
end

class Side
  attr_accessor :id, :category_id, :url, :name, :description, :allergen_warning
  attr_accessor :combo

  def initialize(element)
    return unless element["iname"]

    link = element["href"]
    parts = link.split("/")
    side_id = parts.pop
    category_id = parts.pop
    # some_other_number = parts.pop # TODO: figure out what this is

    description = element.css(".menu_itemList_item_text").first
    description = description.text if description

    allergen_warning = element.css(".js-menuSetHeight_allergen").first
    allergen_warning = allergen_warning.text if allergen_warning

    self.url = "https://order.dominos.jp#{link}"
    self.id = side_id # shohinC
    self.category_id = category_id # categoryC
    self.name = element["iname"]
    self.description = description
    self.allergen_warning = allergen_warning
  end

  def valid?
    url != nil
  end

  def customizable?
    available_combos.count > 0
  end

  def available_combos
    @available_combos ||=
      detail_page_content.css(".m-section_item__changeSide .m-input__radio").map do |option|
        Side::Combo.new(option)
      end.sort_by { |cmb| cmb.default ? 0 : 1 }
  end

  def params
    {
      "shohinC" => id,
      "categoryC" => category_id,
      "setRecommendYosoData" => combo.value
    }
  end

  def list_item
    allergen = allergen_warning || ""

    "#{name.colorize(:blue)} "\
    "#{allergen.strip.colorize(:yellow)}\n  "\
    "#{description.gsub(",", ", ").gsub(")", ") ")}\n".sub("\n  \n", "")
  end

  private

  def detail_page_content
    @detail_page_content ||= Nokogiri::HTML(
      Request.get(url, expect: :ok, failure: "Couldn't open side detail page").body
    )
  end
end

class Side
  class Combo
    attr_accessor :title, :price, :value, :setvalue, :default

    def initialize(option)
      self.title = option.css(".radio_side_title").text.strip
      self.price = option.css(".radio_side_prise_set").text.strip
      self.value = option.css("input[name=setRecommendYosoData]").first["value"]
      self.default = (title == "No thanks")
    end

    def list_item
      [title, price.colorize(:blue)].join(price == "" ? "" : ": ")
    end
  end
end

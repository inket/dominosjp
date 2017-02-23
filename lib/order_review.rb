# frozen_string_literal: true
class OrderReview
  attr_accessor :page
  attr_accessor :total_price, :total_price_without_tax

  def display
    puts
    puts
    puts "Review Your Order".colorize(:red)

    source = page || default_page

    # Order items
    puts OrderItems.from(source)
    puts CouponItems.from(source)

    # General information
    puts retrieve_prices(source)
  end

  private

  def retrieve_prices(source)
    doc = Nokogiri::HTML(source)
    total_price_element = doc.css(".totalPrice_taxin")
    total_price_title = total_price_element.css("dt").text.strip.gsub(/\s+/, " ")
    total_price_string = total_price_element.css("dd").text.strip.gsub(/\s+/, " ")

    self.total_price = total_price_string.delete(",").scan(/¥(\d+)/).flatten.first.to_i
    self.total_price_without_tax = total_price / 108 * 100 # 8% tax

    "\n#{total_price_title}: #{total_price_string.colorize(:red)}\n"\
      "#{doc.css(".totalPrice_tax").text}"
  end

  def default_page
    Request.get("https://order.dominos.jp/eng/pizza/search/",
                expect: :ok, failure: "Couldn't get pizza list page").body
  end
end

class OrderItems < Array
  def self.from(source)
    doc = Nokogiri::HTML(source)
    order_items = doc.css(".m-side_orderItems li").map { |item| OrderItem.new(item) }
    OrderItems.new(order_items)
  end

  def to_s
    map(&:to_s).join("\n")
  end
end

class OrderItem
  attr_accessor :name, :details

  def initialize(item)
    self.name = item.css(".orderItems_item_name").first.text.strip.gsub(/\s+/, " ")
    # TODO: Get toppings list

    details_element = item.css(".orderItems_item_detail")
    details_dt = details_element.css("dt").map { |t| t.text.strip.gsub(/\s+/, " ") }
    details_dd = details_element.css("dd").map { |t| t.text.strip.gsub(/\s+/, " ") }

    self.details = details_dt.zip(details_dd).to_h
    details["Price"] = item.css(".orderItems_item_price").text.strip.gsub(/\s+/, " ")
  end

  def to_s
    deets = details.map { |key, value| "  #{key}: #{value}" }.join("\n")
    "#{name.colorize(:blue)}\n#{deets}"
  end
end

class CouponItems < Array
  def self.from(source)
    doc = Nokogiri::HTML(source)
    coupon_items = doc.css(".m-side_useCoupon li").map { |item| CouponItem.new(item) }

    CouponItems.new(coupon_items)
  end

  def to_s
    return unless count > 0
    "\nCoupons".colorize(:green)
  end
end

class CouponItem
  attr_accessor :name, :value

  def initialize(item)
    self.name = item.css(".useCoupon_coupons_name").text.strip.gsub(/\s+/, " ").sub("\\", "¥")
    self.value = item.css("dd span").text.strip
  end

  def to_s
    "  #{name} #{value.colorize(:green)}"
  end
end

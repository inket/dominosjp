# frozen_string_literal: true
class OrderCoupon
  attr_accessor :total_price_without_tax
  attr_accessor :add_coupon
  attr_accessor :coupon

  def input
    self.add_coupon = Ask.confirm "Add a coupon?"
    return unless add_coupon

    response = Request.get("https://order.dominos.jp/eng/coupon/use/",
                           expect: :ok, failure: "Couldn't get coupons list")

    coupons = Coupons.from(response.body, total_price_without_tax)
    selected_coupon_index = Ask.list "Choose a coupon", coupons.selection_list
    self.coupon = coupons[selected_coupon_index]
  end

  def validate
    return unless add_coupon

    unless coupon.usable?
      puts "This coupon cannot be used."
      return
    end

    Request.post("https://order.dominos.jp/eng/webapi/sides/setUserCoupon/", coupon.params,
                 expect: :ok, failure: "Couldn't add coupon")
  end
end

class Coupons < Array
  def self.from(source, total_price_without_tax)
    doc = Nokogiri::HTML(source)
    coupons = doc.css("li").map { |item| Coupon.new(item, total_price_without_tax) }

    # Sort coupons by real value, expiration date while deranking those that cannot be used (error)
    coupons = [coupons.reject(&:error), coupons.select(&:error)].map do |coups|
      coups.group_by(&:real_value).sort.reverse.map do |_real_value, same_value_coupons|
        same_value_coupons.sort_by(&:expiry)
      end
    end.flatten

    Coupons.new(coupons)
  end

  def selection_list
    map(&:list_item)
  end
end

class Coupon
  attr_accessor :name, :expiry, :error, :couponcd, :couponseq, :expires_soon, :real_value

  def initialize(item, total_price_without_tax)
    name_element_text = item.css("h4").text
    coupon_name = name_element_text.sub("\\", "¥").sub("Expires soon", "")
    expires_soon = name_element_text.include?("Expires soon") ? "Expires soon" : ""

    coupon_link = item.css(".jso-userCuponUse").first || {}

    yen_value = coupon_name.scan(/¥(\d+)/).flatten.first.to_i
    percent_value = coupon_name.scan(/(\d+)%/).flatten.first.to_i

    if yen_value != 0
      real_value = yen_value * 1.08 # 8% tax
    elsif percent_value != 0
      real_value = (total_price_without_tax / (100 / percent_value)) * 1.08 # 8% tax
    end

    error = item.css(".m-input__error").text
    error = error && error.strip != "" ? "\n    #{error}" : nil

    self.name = coupon_name
    self.expiry = item.css(".m-entryPeriod").text.scan(/\d{4}-\d{2}-\d{2}/).first
    self.error = error
    self.couponcd = coupon_link["couponcd"]
    self.couponseq = coupon_link["couponseq"]
    self.expires_soon = expires_soon
    self.real_value = real_value.to_i
  end

  def usable?
    couponcd && couponseq
  end

  def params
    { couponcd: couponcd, couponseq: couponseq }.compact
  end

  def list_item
    "#{name.colorize(:blue)} (-¥#{real_value.to_s.colorize(:green)}) "\
    "#{expires_soon.colorize(:yellow)} #{expiry} #{error.to_s.colorize(:red)}".strip
  end
end

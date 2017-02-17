require "colorize"
require "highline"
require "inquirer"
require "nokogiri"

require_relative "request"
require_relative "order_address"
require_relative "order_coupon"
require_relative "order_information"
require_relative "order_payment"
require_relative "order_review"
require_relative "pizza"
require_relative "pizza_selector"

class DominosJP
  attr_accessor :order_address, :order_information
  attr_accessor :order_review
  attr_accessor :order_coupon, :order_payment

  def initialize(email:, password:)
    @email = email
    @password = password

    self.order_address = OrderAddress.new
    self.order_information = OrderInformation.new
    self.order_review = OrderReview.new
    self.order_coupon = OrderCoupon.new
    self.order_payment = OrderPayment.new
  end

  def login
    Request.post(
      "https://order.dominos.jp/eng/login/login/",
      { "emailAccount" => @email, "webPwd" => @password },
      expect: :redirect, failure: "Couldn't log in successfully"
    )
  end

  def order
    order_address.input
    order_address.validate

    order_information.input
    order_information.validate
    order_information.display
    order_information.confirm

    PizzaSelector.select_pizzas
    # TODO: allow selecting sides

    order_review.display

    order_coupon.total_price_without_tax = order_review.total_price_without_tax
    order_coupon.input
    order_coupon.validate

    order_review.display

    order_payment.default_name = order_information.name
    order_payment.input
    order_payment.validate
    order_payment.display

    order_review.page = order_payment.page
    order_review.display

    order_payment.confirm
  end
end

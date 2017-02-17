require "net/http"
require "http-cookie"
require "singleton"

class Request
  include Singleton

  def self.get(url, options = {})
    request = Net::HTTP::Get.new(URI(url))

    Request.instance.perform(
      request,
      block_given? ? options.merge(proc: Proc.new { |res| yield(res) }) : options
    )
  end

  def self.post(url, form_data, options = {})
    request = Net::HTTP::Post.new(URI(url))
    request.set_form_data(form_data)

    Request.instance.perform(
      request,
      block_given? ? options.merge(proc: Proc.new { |res| yield(res) }) : options
    )
  end

  def initialize
    @base_uri = URI("https://order.dominos.jp/eng/")
    @http = Net::HTTP.start(@base_uri.host, @base_uri.port, use_ssl: true)
    @jar = HTTP::CookieJar.new
  end

  def perform(request, options)
    request["Cookie"] = cookies_value
    response = @http.request(request)

    save_cookies(response)
    parse_options(options, response)

    response
  end

  private

  def cookies_value
    HTTP::Cookie.cookie_value(@jar.cookies(@base_uri))
  end

  def save_cookies(response)
    response.get_fields('Set-Cookie').each do |value|
      @jar.parse(value, @base_uri)
    end
  end

  def parse_options(options, response)
    validate_status(options, response) if options[:expect]
    validate_block(options, response) if options[:proc]
  end

  def validate_status(options, response)
    expectation, redirect, failure = options.values_at(:expect, :to, :failure)
    expectation = { ok: 200, redirect: 302 }[expectation] if expectation.is_a?(Symbol)

    correct_status = (response.code.to_i == expectation)
    correct_location = redirect == nil ||
                       (redirect == response["Location"]) ||
                       (redirect.is_a?(Regexp) && redirect.match(response["Location"]))

    unless correct_status && correct_location
      failure_message =
        failure ||
        "Expected a different server response. "\
        "(expected: #{options} / actual: #{response.code}[#{response['Location']}])"

      puts failure_message.colorize(:red)
      raise failure_message
    end
  end

  def validate_block(options, response)
    expectation, failure = options.values_at(:proc, :failure)

    unless expectation.call(response)
      failure_message = failure || "Expected a different server response. "

      puts failure_message.colorize(:red)
      raise failure_message
    end
  end
end

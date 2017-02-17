require "yaml"

class Preferences
  include Singleton

  attr_accessor :email, :name, :phone_number, :credit_card, :note

  def initialize
    preferences_path = File.join(Dir.home, ".dominosjp.yml")
    return unless File.exist?(preferences_path)

    prefs = YAML.load(File.read(preferences_path))

    self.email = prefs[:email] if prefs[:email]
    self.name = prefs[:name] if prefs[:name]
    self.phone_number = prefs[:phone_number] if prefs[:phone_number]
    self.credit_card = CreditCard.new(prefs[:credit_card]) if prefs[:credit_card]
    self.note = prefs[:note] if prefs[:note]
  end
end

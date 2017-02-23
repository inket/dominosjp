# frozen_string_literal: true
class SideSelector
  def self.select_sides
    return unless Ask.confirm "Add sides?"

    response = Request.get("https://order.dominos.jp/eng/side/search/",
                           expect: :ok, failure: "Couldn't get side list page")

    sides = Sides.from(response.body)

    cli = HighLine.new
    choices = sides.selection_list

    loop do
      puts "-" * 42
      cli.choose do |menu|
        menu.prompt = "Add a side via number:"
        menu.choices(*(choices + ["Cancel"])) do |choice|
          index = choices.index(choice)

          if index && index < choices.count
            selected_side = sides[index]

            puts "#{"→".colorize(:green)} #{selected_side.name.colorize(:blue)}"
            add_side(customize_side(selected_side))
          end
        end
        menu.default = "Cancel"
      end

      break unless Ask.confirm "Add another side?"
    end
  end

  def self.customize_side(side)
    return side unless side.customizable?

    # Choosing the combo
    selected_combo_index = Ask.list "Choose the combo", side.available_combos.map(&:list_item)
    side.combo = side.available_combos[selected_combo_index]

    side
  end

  def self.add_side(side)
    params = side.params.merge(
      "pageId" => "SIDE_DETAIL",
      "shohinPretotypingCouponC" => "",
      "figure" => "1" # Quantity
    )

    response = Request.post(
      "https://order.dominos.jp/eng/cart/add/side/", params,
      expect: :redirect, to: %r{\Ahttps?://order\.dominos\.jp/eng/cart/added/\z},
      failure: "Couldn't add the side you selected"
    )

    # For some reason we need to GET this URL otherwise it doesn't count as added <_<
    Request.get(response["Location"],
                expect: :redirect, to: "https://order.dominos.jp/eng/cart/",
                failure: "Couldn't add the side you selected")
  end
end

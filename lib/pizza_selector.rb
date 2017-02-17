class PizzaSelector
  def self.select_pizzas
    response = Request.get("https://order.dominos.jp/eng/pizza/search/",
                           expect: :ok, failure: "Couldn't get pizza list page")

    pizzas = Pizzas.from(response.body)

    cli = HighLine.new
    choices = pizzas.selection_list

    loop do
      puts "-" * 42
      cli.choose do |menu|
        menu.prompt = "Add a pizza via number:"
        menu.choices(*(choices + ["Cancel"])) do |choice|
          index = choices.index(choice)

          if index && index < choices.count
            selected_pizza = pizzas[index]
            add_pizza(customize_pizza(selected_pizza))
          end
        end
        menu.default = "Cancel"
      end

      break unless (Ask.confirm "Add another pizza?")
    end
  end

  def self.customize_pizza(pizza)
    puts "#{"→".colorize(:green)} #{pizza.name.colorize(:blue)}"

    # TODO: Allow toppings selection

    # Choosing the size
    selected_size_index = Ask.list "Choose the size", pizza.available_sizes.map(&:list_item)
    pizza.size = pizza.available_sizes[selected_size_index]

    # Choosing the crust
    selected_crust_index = Ask.list "Choose the crust", pizza.available_crusts.map(&:list_item)
    pizza.crust = pizza.available_crusts[selected_crust_index]

    pizza
  end

  def self.add_pizza(pizza)
    params = pizza.params
    params = params.merge(
      "pageId" => "PIZZA_DETAIL",
      # TODO: Allow cut type, number of slices and quantity selection
      "cutTypeC" => 1, # Type of cut: 1=Round Cut
      "cutSu" => 8, # Number of slices
      "figure" => 1  # Quantity
    )

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
end

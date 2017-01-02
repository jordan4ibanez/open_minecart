minetest.register_craftitem("open_minecart:minecart", {
	description = "open_minecart",
	inventory_image = minetest.inventorycube("carts_cart_top.png", "carts_cart_side.png", "carts_cart_side.png"),
	wield_image = "carts_cart_side.png",
	on_place = function(itemstack, placer, pointed_thing)
		if not pointed_thing.type == "node" then
			return
		end
		if carts:is_rail(pointed_thing.under) then
			minetest.add_entity(pointed_thing.under, "open_minecart:minecart")
		elseif carts:is_rail(pointed_thing.above) then
			minetest.add_entity(pointed_thing.above, "open_minecart:minecart")
		else
			return
		end

		minetest.sound_play({name = "default_place_node_metal", gain = 0.5},
			{pos = pointed_thing.above})

		if not minetest.setting_getbool("creative_mode") then
			itemstack:take_item()
		end
		return itemstack
	end,
})

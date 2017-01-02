dofile(minetest.get_modpath("open_minecart").."/items.lua")

minetest.register_entity("open_minecart:minecart", {
	--Do simpler definition variables for ease of use
	minecart     = true,
	
	collisionbox = {-0.45,-0.45,-0.45,0.45,0.45,0.45,},
	height       = -0.45, --sample from bottom of collisionbox - absolute for the sake of math
	width        = 0.45, --sample first item of collisionbox
	--vars for collision detection and floating
	overhang     = 0.45,
	--create variable that can be added to pos to find center
	center = 0,
	
	
	--physical variables
	collision_radius = 1, -- collision sphere radius
	physical     = true,
	collide_with_objects = false, -- for magnetic collision
	max_velocity = 8, --how fast a cart can move
	acceleration = 12, --the elasticity of collision detection and acceleration
	automatic_face_movement_dir = 90, --for smoothness
	yaw = 0,
	velocity = 0,
	pitch = 0,
	direction = {x=0,y=0,z=0},
	on_rail  = false,--if it's within a rail node
	is_rail  = false,--if there's a rail in front of it
	
	--aesthetic variables
	visual = "mesh",
	mesh = "carts_cart.b3d",
	textures = {"carts_cart.png"},
	visual_size = {x=1,y=1},
	
	--[[
	--Aesthetic variables
	visual   = def.visual,
	mesh     = def.mesh,
	textures = def.textures,
	makes_footstep_sound = def.makes_footstep_sound,
	animation = def.animation,
	visual_size = {x=def.visual_size.x, y=def.visual_size.y},
	eye_offset = def.eye_offset,
	visual_offset = def.visual_offset,
	player_pose = def.player_pose,
	
	
	--Behavioral variables
	behavior_timer      = 0, --when this reaches behavior change goal, it changes states and resets
	behavior_timer_goal = 0, --randomly selects between min and max time to change direction
	behavior_change_min = def.behavior_change_min,
	behavior_change_max = def.behavior_change_max,
	update_timer        = 0,
	follow_item         = def.follow_item,
	leash               = def.leash,
	leashed             = false,
	in_cart             = false,
	rides_cart          = def.rides_cart,
	rideable            = def.rideable,
	
	--taming variables
	tameable            = def.tameable,
	tame_item           = def.tame_item,
	owner               = nil,
	owner_name          = nil,
	tamed               = false,
	tame_click_min      = def.tame_click_min,
	tame_click_max      = def.tame_click_max,
	--chair variables - what the player sits on
	mob_chair           = def.mob_chair,
	has_chair           = false,
	chair_textures      = def.chair_textures,
	
	
	
	--Physical variables
	old_position = nil,
	yaw          = 0,
	jump_timer   = 0,
	jump_height  = def.jump_height,
	float        = def.float,
	liquid       = 0,
	hurt_velocity= def.hurt_velocity,
	liquid_mob   = def.liquid_mob,
	attached     = nil,
	attached_name= nil,
	jump_only    = def.jump_only,
	jumped       = false,
	scale_size   = 1,
	
	
	--Pathfinding variables
	path = {},
	target = nil,
	target_name = nil,
	following = false,
	]]--
	--Internal variables
	age = 0,
	time_existing = 0, --this won't be saved for static data polling
	
	
	--what mobs do when created
	on_activate = function(self, staticdata, dtime_s)
		--print("activating at "..dump(self.object:getpos()))
		if string.sub(staticdata, 1, string.len("return")) == "return" then
			local data = minetest.deserialize(staticdata)
			for key,value in pairs(data) do
				self[key] = value
			end
		end
	end,

	
	
	
	
	
	--when the mob entity is deactivated
	get_staticdata = function(self)
		local serialize_table = {}
		for key,value in pairs(self) do
			--don't get object item
			if key ~= "object" and key ~= "time_existing" then
				--don't do userdata
				if type(value) == "userdata" then
					value = nil
				end
				serialize_table[key] = value
			end
		end
		--manually save collisionbox
		--serialize_table["collisionbox"] = self.collisionbox
		local value_string = minetest.serialize(serialize_table)
		return(value_string)
	end,
	
	--how the mob collides with other mobs and players
	collision = function(self)
		local pos = self.object:getpos()
		pos.y = pos.y + self.height -- check bottom of mob
		
		local vel = self.object:getvelocity()
		local x   = 0
		local z   = 0
		for _,object in ipairs(minetest.env:get_objects_inside_radius(pos, 1)) do
			--only collide with minecarts, mobs, and players
						
			--add exception if a nil entity exists around it
			if object:is_player() or ((object:get_luaentity() and object:get_luaentity().mob == true and object ~= self.object)) or (object:get_luaentity() and object:get_luaentity().minecart == true and object ~= self.object) then
				local pos2 = object:getpos()
				local vec  = {x=pos.x-pos2.x, z=pos.z-pos2.z}
				--push away harder the closer the collision is, could be used for mob cannons
				--+0.5 to add player's collisionbox, could be modified to get other mobs widths
				local force = (1) - vector.distance({x=pos.x,y=0,z=pos.z}, {x=pos2.x,y=0,z=pos2.z})--don't use y to get verticle distance
				--modify existing value to magnetize away from mulitiple entities/players
				x = x + (vec.x * force) * 20
				z = z + (vec.z * force) * 20
			end
		end
		return({x,z})
	end,

	
	-- how a minecarts moves around the world
	movement = function(self,dtime)
		--self.collide_with_terrain(self)
	
		--move cart to goal velocity using acceleration for smoothness
		local vel = self.object:getvelocity()		
		local collide_values = self.collision(self)
		
		
		--call this variables to 0 and only change when needed
		local c_x = 0
		local c_z = 0
		local x   = 0
		local z   = 0
		
		--only collision detect on axis when on a rail
		--if on rail and rail in front of then call this
		if self.on_rail == true and self.velocity > 0 and self.turning ~= true then
			--prefer x over z for no particular reason
			--preference is to only call one axis when riding rail as to not push off rail
			x   = math.sin(self.yaw) * -self.velocity
			z   = math.cos(self.yaw) * self.velocity
			if self.direction.x ~= 0 then
				c_x = collide_values[1]
			elseif self.direction.z ~= 0 then
				c_z = collide_values[2]
			end
		--if not on rail, collision detect like normal
		--allow player to push minecart onto rail, or push it around rails
		else
			c_x = collide_values[1]
			c_z = collide_values[2]
			x   = math.sin(self.yaw) * -self.velocity
			z   = math.cos(self.yaw) * self.velocity
		end
		
		
		

		local gravity = -10
		self.object:set_properties({physical = true,})
		if (self.is_rail == true and self.pitch ~= 0) or (self.is_rail == true and (math.floor(vel.y+0.5) > 0 or math.floor(vel.y+0.5) < 0)) then
			gravity = self.pitch
			--ghost through nodes when going up
			self.object:set_properties({physical = false,})
		end
		
		
		if self.turning ~= true then
		--on ground
		if gravity == -10 then 
			self.object:setacceleration({x=(x - vel.x + c_x)*self.acceleration,y=-10,z=(z - vel.z + c_z)*self.acceleration})				
		--on rail
		else 
			self.object:setacceleration({x=(x - vel.x + c_x)*self.acceleration,y=(gravity-vel.y)*self.acceleration,z=(z - vel.z + c_z)*self.acceleration})
		end
		else
			--navigating a turn
			local mult = vector.multiply(self.direction, self.velocity)
			self.object:setvelocity({x=x,y=0,z=z})
		end
		
		--set the velocity if colliding
		if (vel.x ~= 0 or vel.z ~= 0) and (c_x ~= 0 or c_z ~= 0) then
			local newspeed = vector.length({x=c_x,y=0,z=c_z})
			--only set if greater
			if newspeed > self.velocity then
				self.velocity = newspeed
			end
		end
		
		--this will overwrite the inertia set by the setting self.velocity
		self.inertia(self)
		
	end,

	--slow the minecart down
	inertia = function(self)
		--print(self.velocity)
		if self.velocity > 0 then
			self.velocity = self.velocity - 0.02
		elseif self.velocity <= 0 then
			self.velocity = 0
		end		
	end,

	

	--check if node is rail
	check_rail = function(name)
		local group = minetest.get_item_group(name, "rail")
		return(group)
	end,
	
	--find next rail or simply give up and crash off the rails
	--hooked into the already opened vm
	next_rail = function(self,vm,area,data)
		local pos = self.object:getpos()
		local vel = self.object:getvelocity()
		local floorpos = vector.round(self.object:getpos()) --floor the position to get absolute accuracy
		self.direction = vector.round(vector.normalize(vel)) --normalize the direction that the cart is going in
		
		--check squarely in front of the cart
		local p_pos = area:index(floorpos.x+self.direction.x,floorpos.y,floorpos.z+self.direction.z)
		local name = minetest.get_name_from_content_id(data[p_pos])
		--convert to bool
		self.is_rail = (1 == self.check_rail(name))
		
		--this function divides real pos by goal node pos to get smooth movement
		
		--reset variables
		self.turning = false
		self.pitch = 0
		
		--try to go up or down slope
		if self.is_rail == false and self.direction then
			for y = -1,1 do
				local p_pos = area:index(floorpos.x+self.direction.x,floorpos.y+y,floorpos.z+self.direction.z)
				local name = minetest.get_name_from_content_id(data[p_pos])
				self.is_rail = (1 == self.check_rail(name))
				if self.is_rail == true then
					--go faster downhill
					--also wait until past node center to go down
					if y < 0 and vector.distance(pos,vector.add(floorpos,self.direction)) <= 1 then
						if self.velocity < self.max_velocity then
							self.velocity = self.velocity + 1
						end
						self.pitch = (y*self.velocity)
						self.direction.y = y
						self.object:setvelocity(vector.multiply(self.direction,self.velocity))
					else
						self.pitch = (y*self.velocity)
						self.direction.y = y
						self.object:setvelocity(vector.multiply(self.direction,self.velocity))
					end
					self.old_yer = y
					break
				end
			end
		end
		
		--debug to get carts to follow in a straight line
		if self.is_rail == true and self.direction then
			local pos2 = vector.add(floorpos,self.direction)
			
			local vec = {x=pos.x-pos2.x,y=pos.y-pos2.y, z=pos.z-pos2.z}
			
			--avoid dividing by 0
			if vec.x ~= 0 or vec.z ~= 0 then
			
				self.yaw = math.atan(vec.z/vec.x)+ math.pi / 2
			
				if pos2.x > pos.x then
					self.yaw = self.yaw+math.pi
				end
				
				
				--self.pitch = (vec.y*self.velocity)*-1
				
			end
		--try to change dir
		elseif self.is_rail == false and self.direction then
			--if x then go to z
			if self.direction.x ~= 0 then
				--will always prefer -z if possible
				for z = -1,1 do
					if z ~= 0 then
					local p_pos = area:index(floorpos.x,floorpos.y,floorpos.z+z)
					local name = minetest.get_name_from_content_id(data[p_pos])
					
					self.is_rail = (1 == self.check_rail(name))
					
					--if found rail then change yaw to it and head to it
					if self.is_rail == true then
						local pos2 = {x=floorpos.x,y=floorpos.y,z=floorpos.z+z}
			
						local vec = {x=pos.x-pos2.x,y=pos.y-pos2.y, z=pos.z-pos2.z}
						
						--avoid dividing by 0
						if vec.x ~= 0 or vec.z ~= 0 then
						
							self.yaw = math.atan(vec.z/vec.x)+ math.pi / 2
						
							if pos2.x > pos.x then
								self.yaw = self.yaw+math.pi
							end
							self.turning = true
						end
						
								
						return
					end
					end
				end
			--if z then go to x
			elseif self.direction.z ~= 0 then
			--will always prefer -x if possible
				for x = -1,1 do
					if x ~= 0 then
					local p_pos = area:index(floorpos.x+x,floorpos.y,floorpos.z)
					local name = minetest.get_name_from_content_id(data[p_pos])
					
					self.is_rail = (1 == self.check_rail(name))
					
					--if found rail then change yaw to it and head to it
					if self.is_rail == true then
						local pos2 = {x=floorpos.x+x,y=floorpos.y,z=floorpos.z}
			
						local vec = {x=pos.x-pos2.x,y=pos.y-pos2.y, z=pos.z-pos2.z}
						
						--avoid dividing by 0
						if vec.x ~= 0 or vec.z ~= 0 then
						
							self.yaw = math.atan(vec.z/vec.x)+ math.pi / 2
						
							if pos2.x > pos.x then
								self.yaw = self.yaw+math.pi
							end
							
							self.turning = true
						end
								
						return
					end
					end
				end
				--
			
			end
		
		end
		
	end,
		
	
	--how a cart rides rails
	ride_rail = function(self)
	
		local vel = self.object:getvelocity()
		local pos = vector.round(self.object:getpos())
		
		
		
		--open voxel manip object
		local min = {x=pos.x-1,y=pos.y-1,z=pos.z-1}
		local max = {x=pos.x+1,y=pos.y+1,z=pos.z+1}
		local vm = minetest.get_voxel_manip()	
		local emin, emax = vm:read_from_map(min,max)
		local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
		local data = vm:get_data()
		
		
		--check if on rail
		local p_pos = area:index(pos.x,pos.y,pos.z)
							
		local name = minetest.get_name_from_content_id(data[p_pos])
		
		--convert to bool
		self.on_rail = (1 == self.check_rail(name))
		
		
		--on rail
		if self.on_rail == true or self.is_rail == true then
			self.next_rail(self,vm,area,data)
		else
			--just give up and go off the rails
			self.velocity = 0
			self.pitch = 0
		end
		
		

		
		vm = nil
		data = nil
		area = nil
		
	end,






	






	--remember total age and time existing since spawned
	find_age = function(self,dtime)
		self.age = self.age + dtime
		self.time_existing = self.time_existing + dtime
	end,

	
	--what mobs do on each server step
	on_step = function(self,dtime)
		self.movement(self,dtime)
		self.ride_rail(self)
		self.find_age(self,dtime)
	end,
	
	
})

var position_controller
var pathfinding
var abstract_map
var action_controller
const LOOKUP_RANGE = 10
var actions = {}
var current_player_ap = 0
var current_player

const ACTION_ATTACK = 0
const ACTION_MOVE   = 1
const ACTION_CAPTURE = 2
const ACTION_SPAWN = 3
const ACTION_MOVE_TO_ATTACK = 4
const ACTION_MOVE_TO_CAPTURE = 5

const SPAWN_LIMIT = 25
const DEBUG = false
var terrain
var units
var buildings
var enemy_bunker

var actionObject = preload('actions/action_object.gd')

func gather_available_actions(player_ap):
	#generate new seed
	randomize()
	current_player = action_controller.current_player
	current_player_ap = player_ap
	actions = {}
	# refreshing unit and building data
	position_controller.refresh()
	if DEBUG:
		print('DEBUG -------------------- ')
	buildings = position_controller.get_player_buildings(current_player)
	units     = position_controller.get_player_units(current_player)
	terrain   = position_controller.get_terrain_obstacles()

	self.gather_building_data(buildings, units)
	self.gather_unit_data(buildings, units, terrain)

	return self.execute_best_action()

func _prepare_cost_maps(own_buildings, own_units, terrain):
	var cost_maps = {}
	# for each unit type
	for unit_type in range(0,3):
		cost_maps[unit_type] = pathfinding.prepareCostMap(abstract_map.tiles_cost_map[unit_type], own_units, own_buildings, terrain)

	return cost_maps

func gather_unit_data(own_buildings, own_units, terrain):
	if own_units.size() == 0:
		return

	var cost_maps = self._prepare_cost_maps(own_buildings, own_units, terrain)
	for pos in own_units:
		var unit = own_units[pos]
		if unit.get_ap() < 2:
			return
		var position = unit.get_pos_map()

		# this should be already map for use in pathfinding


		var nearby_tiles = position_controller.get_nearby_tiles(position, LOOKUP_RANGE)

		var destinations = []

		destinations = position_controller.get_nearby_enemy_buldings(nearby_tiles, current_player)
		destinations = destinations + position_controller.get_nearby_empty_buldings(nearby_tiles)
		destinations = destinations + position_controller.get_nearby_enemies(nearby_tiles, current_player)
		self.gather_random_nearby_tile(unit)
		for destination in destinations:
			self.add_action(unit, destination, cost_maps[unit.get_type()])


func gather_random_nearby_tile(unit):
	var position = unit.get_pos_map()
	var tiles = {}
	var nearby_tiles = position_controller.get_nearby_tiles(position, 1)


func gather_building_data(own_buildings, own_units):
	if own_units.size() >= SPAWN_LIMIT:
		return

	var buildings = position_controller.get_player_buildings(current_player)
	for pos in own_buildings:
		var building = own_buildings[pos]
		var nearby_tiles = position_controller.get_nearby_tiles(building.get_pos_map(), LOOKUP_RANGE)
		var enemy_units = position_controller.get_nearby_enemies(nearby_tiles, current_player)

		self.add_building_action(building, enemy_units, own_units)

func add_action(unit, destination, cost_map):
	var path = pathfinding.pathSearch(unit.get_pos_map(), destination.get_pos_map())
	var action_type = ACTION_MOVE
	var hiccup = false
	if path.size() == 0:
		return

	# jakies solidne WTF?
	if (unit.get_pos_map() == path[0]):
		path.remove(0)

	if path.size() > 0:
		# skip if this can be capture move and building cannot be captured
		var unit_ap_cost = 0
		var tile_ap = 0
		# verify action_type
		var next_tile = abstract_map.get_field(path[0])

		if (next_tile.object != null):
			if(next_tile.object.group == 'building'):
				if unit.can_capture_building(next_tile.object):
					action_type = ACTION_CAPTURE
				else:
					return # if cannot capture he canot move
			elif next_tile.object.group == 'unit':
				if unit.can_attack_unit_type(next_tile.object) && unit.can_attack():
					action_type = ACTION_ATTACK
				else:
					return
			# elif next_tile.object.group == "terrain":
			# 	return # no tresspassing
		else:
			var from = action_controller.abstract_map.get_field(unit.get_pos_map())
			var to = action_controller.abstract_map.get_field(path[0])
			if not action_controller.movement_controller.can_move(from, to):
				return

			action_type = ACTION_MOVE
			unit_ap_cost = abstract_map.calculate_path_cost(unit, path)
			var last_tile = abstract_map.get_field(path[path.size() - 1])
			if (last_tile.object != null):
				if (last_tile.object.group == 'building'):
					if (unit.can_capture_building(last_tile.object)):
						action_type = ACTION_MOVE_TO_CAPTURE

				elif(last_tile.object.group == 'unit'):
					if (unit.can_attack_unit_type(last_tile.object)):
						action_type = ACTION_MOVE_TO_ATTACK

			# checking for movement hiccup (only for movement)
			hiccup = unit.check_hiccup(path[0])


		var score = unit.estimate_action(action_type, path.size(), unit_ap_cost, hiccup)
		if DEBUG:
			print("DEBUG : ", self.get_action_name(action_type), " score: ", score, " ap: ", unit_ap_cost," pos: ",unit.get_pos_map()," path: ", path)
		self.append_action(actionObject.new(unit, path, action_type), score)

func get_action_name(type):
	if type == ACTION_MOVE:
		return 'MOVE'
	elif type == ACTION_CAPTURE:
		return 'CAPTURE'
	elif type == ACTION_SPAWN:
		return 'SPAWN'
	elif type == ACTION_MOVE_TO_ATTACK:
		return 'MOVE ATTACK'
	elif type == ACTION_MOVE_TO_CAPTURE:
		return 'MOVE CAPTURE'
	else:
		return 'ATTACK'

func add_building_action(building, enemy_units_nearby, own_units):
	var action_type = ACTION_SPAWN
	var spawn_point = abstract_map.get_field(building.spawn_point)
	if (spawn_point.object == null && building.get_required_ap() <= current_player_ap):
		var score = building.estimate_action(action_type, enemy_units_nearby, own_units)
		if DEBUG:
			print("DEBUG : ", self.get_action_name(action_type), " score: ", score, " ap: ", building.get_required_ap())
		self.append_action(actionObject.new(building, null, action_type), score)

func append_action(action, score):
	if actions.has(score):
		score = score + floor(randf() * 20)

	actions[score] = action

func execute_best_action():
	# last element of sorted keys
	var action = null
	var size = actions.size()
	if (size > 0):
		action = actions[self.get_max_key(actions.keys())]
		if action.type == ACTION_SPAWN:
			self.execute_spawn(action)
		elif action.type == ACTION_ATTACK:
			self.execute_attack(action)
		elif action.type == ACTION_CAPTURE:
			self.execute_capture(action)
		else:
			self.execute_move(action)

		return true

	return false

func get_max_key(keys):
	var max_key = -999
	for key in keys:
		if (key > max_key):
			max_key = key

	return max_key

func execute_spawn(action):
	action_controller.set_active_field(action.unit.get_pos_map())
	action_controller.spawn_unit_from_active_building()

func execute_move(action):
	var active_field = action_controller.set_active_field(action.unit.get_pos_map())
	var field = self.get_next_tile_from_action(action)
	if field:
#		action_controller.move_unit(active_field, field)
		action_controller.handle_action(field.position)

func execute_attack(action):
	var active_field = action_controller.set_active_field(action.unit.get_pos_map())
	var field = self.get_next_tile_from_action(action)
	if field:
#		action_controller.handle_battle(active_field, field)
		action_controller.handle_action(field.position)

func execute_capture(action):
	var active_field = action_controller.set_active_field(action.unit.get_pos_map())
	var field = self.get_next_tile_from_action(action)
	if field:
#	    action_controller.capture_building(active_field, field)
		action_controller.handle_action(field.position)

func get_next_tile_from_action(action):
	var path = action.path
	if path.size() == 0:
		return null

	return abstract_map.get_field(path[0])

func init(controller, astar_pathfinding, map, action_controller_object):
	position_controller = controller
	pathfinding = astar_pathfinding
	abstract_map = map
	action_controller = action_controller_object
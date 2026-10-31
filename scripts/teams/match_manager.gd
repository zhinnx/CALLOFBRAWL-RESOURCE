## CALLOFBRAWL — Team Deathmatch rules and combatant lifecycle.
##
## Owns
##   * the 5 v 5 roster (1 human + 4 friendly bots vs 5 enemy bots)
##   * the match clock and score limit
##   * elimination attribution (friendly fire can never score)
##   * 3 second respawn queue with safe spawn selection
##   * signal surface consumed by the HUD
class_name CBMatchManager
extends Node

signal match_started
signal time_changed(seconds_left: float)
signal score_changed(alpha: int, bravo: int)
signal eliminated(entry: Dictionary)
signal respawn_countdown(combatant_id: String, seconds_left: float)
signal match_finished(result: Dictionary)

const BOT_NAMES_ALPHA := ["Vulture", "Nomad", "Bishop", "Talon"]
const BOT_NAMES_BRAVO := ["Havoc", "Rook", "Sable", "Kestrel", "Vex"]

var map_loader: CBMapLoader
var player: CBPlayerController
var bots: Array[CBBotController] = []
var player_spawn_index: int = 0

var time_left: float = 600.0
var running: bool = false
var finished: bool = false
var _respawns: Array[Dictionary] = []
var _countdown_fx: float = 0.0
var _last_shown_second: int = -1


func setup(loader: CBMapLoader, local_player: CBPlayerController) -> void:
	map_loader = loader
	player = local_player


# ---------------------------------------------------------------- match flow
func start_match() -> void:
	Game.configure_match()
	time_left = Game.match_minutes * 60.0
	finished = false
	running = true
	Game.begin_match()
	Game.score_changed.connect(_on_score_changed)
	spawn_roster()
	match_started.emit()
	time_changed.emit(time_left)


func spawn_roster() -> void:
	# --- local player
	if player != null:
		var spawn := map_loader.resolve_spawn(CBTeam.ALPHA, player_spawn_index)
		player.configure(Game.local_combatant_id, Settings.get_value("player_name"), CBTeam.ALPHA)
		player.on_spawn(spawn, _yaw_towards_middle(spawn))
		Game.register_combatant(Game.local_combatant_id, str(Settings.get_value("player_name")),
				CBTeam.ALPHA, false, true)
		Game.local_player = player
		player_spawn_index += 1
	# --- bots
	bots.clear()
	var difficulty := Settings.get_int("bot_difficulty")
	for i in BOT_NAMES_ALPHA.size():
		_add_bot("bot_a%d" % i, BOT_NAMES_ALPHA[i], CBTeam.ALPHA, i, difficulty)
	for i in BOT_NAMES_BRAVO.size():
		_add_bot("bot_b%d" % i, BOT_NAMES_BRAVO[i], CBTeam.BRAVO, i, difficulty)


func _add_bot(id: String, bot_name: String, team: int, index: int, difficulty: int) -> void:
	var bot := CBBotController.new()
	bot.name = "Bot_%s" % id
	bot.match_manager = self
	bot.map_loader = map_loader
	# identity must be set *before* the node enters the tree so the visual/weapon
	# rigs built in _ready() already carry the right team colours and ids
	bot.combatant_id = id
	bot.display_name = bot_name
	bot.team = team
	add_child(bot)
	bot.configure(id, bot_name, team, difficulty)
	var spawn := map_loader.resolve_spawn(team, index)
	bot.on_spawn(spawn, _yaw_towards_middle(spawn))
	bots.append(bot)
	Game.register_combatant(id, bot_name, team, true, false)


func _yaw_towards_middle(from: Vector3) -> float:
	var middle := Vector3(-2.0, from.y, 1215.0)
	var flat := middle - from
	return atan2(-flat.x, -flat.z)


# ---------------------------------------------------------------- tick
func _process(delta: float) -> void:
	if not running or finished:
		return
	time_left = maxf(0.0, time_left - delta)
	Game.match_elapsed += delta
	time_changed.emit(time_left)
	if Game.is_score_limit_reached():
		_finish("score_limit")
		return
	if time_left <= 0.0:
		_finish("time_limit")
		return
	_update_respawns(delta)
	# last-10-second countdown beeps
	if time_left <= 10.0:
		var sec := int(ceil(time_left))
		if sec != _last_shown_second:
			_last_shown_second = sec
			Audio.play_ui("countdown", -14.0, 1.0 + (10 - sec) * 0.03)


func _update_respawns(delta: float) -> void:
	if _respawns.is_empty():
		return
	var still: Array[Dictionary] = []
	for entry in _respawns:
		entry["time"] = float(entry.get("time", 0.0)) - delta
		var who: String = str(entry.get("id", ""))
		var remaining := float(entry.get("time", 0.0))
		if remaining <= 0.0:
			_respawn(entry)
		else:
			still.append(entry)
			respawn_countdown.emit(who, remaining)
	_respawns = still


func _respawn(entry: Dictionary) -> void:
	var node: Node = entry.get("node")
	if node == null or not is_instance_valid(node):
		return
	var team: int = int(entry.get("team", CBTeam.ALPHA))
	var pos := map_loader.pick_spawn(team, _living_positions())
	var yaw := _yaw_towards_middle(pos)
	if node is CBBotController:
		(node as CBBotController).on_respawn(pos, yaw)
		Audio.play_3d("respawn", pos, -10.0, 0.05, 25.0)
	elif node is CBPlayerController:
		var p := node as CBPlayerController
		p.on_spawn(pos, yaw)
		Audio.play_ui("respawn", -8.0)
		p.set_aiming(false)
		p.weapon.set_trigger(false)


func _living_positions() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if player != null and player.is_alive:
		out.append(player)
	for bot in bots:
		if bot.is_alive:
			out.append(bot)
	return out


# ---------------------------------------------------------------- deaths
## Called by a bot when it dies.
func on_bot_died(bot: CBBotController, attacker_id: String, headshot: bool) -> void:
	var attacker_name := _name_for(attacker_id)
	var attacker_team := _team_for(attacker_id)
	Game.report_elimination(attacker_id, attacker_name, attacker_team,
			bot.combatant_id, bot.display_name, bot.team, "AK-47", headshot)
	var entry := {
		"attacker": attacker_name,
		"attacker_team": attacker_team,
		"victim": bot.display_name,
		"victim_team": bot.team,
		"headshot": headshot,
	}
	eliminated.emit(entry)
	Audio.play_3d("elimination", bot.global_position, -8.0, 0.05, 30.0)
	# every combatant, including bots, comes back after the configured delay
	begin_respawn_timer(bot)


## Called by the player when it dies (registered in gameplay.gd).
func on_player_died(attacker_id: String, headshot: bool) -> void:
	if not running or finished:
		return
	var victim_name: String = str(Settings.get_value("player_name"))
	var attacker_name := _name_for(attacker_id)
	var attacker_team := _team_for(attacker_id)
	Game.report_elimination(attacker_id, attacker_name, attacker_team,
			Game.local_combatant_id, victim_name, CBTeam.ALPHA, "AK-47", headshot)
	eliminated.emit({
		"attacker": attacker_name,
		"attacker_team": attacker_team,
		"victim": victim_name,
		"victim_team": CBTeam.ALPHA,
		"headshot": headshot,
	})
	begin_respawn_timer(player)


## Queues a combatant for respawn after the configured delay.
func begin_respawn_timer(node: Node) -> void:
	if not running or finished or node == null:
		return
	# never queue the same combatant twice (a stray double death report would otherwise
	# spawn the same body twice)
	for entry in _respawns:
		if entry.get("node") == node:
			return
	var id := ""
	var team := CBTeam.ALPHA
	if node is CBBotController:
		id = (node as CBBotController).combatant_id
		team = (node as CBBotController).team
	elif node is CBPlayerController:
		id = Game.local_combatant_id
		team = (node as CBPlayerController).team
	_respawns.append({"id": id, "node": node, "team": team, "time": Game.respawn_delay})


func _name_for(id: String) -> String:
	if id == "" or id == "world":
		return "Environment"
	var stat := Game.get_stat(id)
	if stat.is_empty():
		return "Unknown"
	return str(stat.get("name", "Unknown"))


func _team_for(id: String) -> int:
	if id == "" or id == "world":
		return CBTeam.NONE
	var stat := Game.get_stat(id)
	if stat.is_empty():
		return CBTeam.NONE
	return int(stat.get("team", CBTeam.NONE))


# ---------------------------------------------------------------- scoring / end
func _on_score_changed(alpha: int, bravo: int) -> void:
	score_changed.emit(alpha, bravo)


func _finish(reason: String) -> void:
	if finished:
		return
	finished = true
	running = false
	Game.match_elapsed = Game.match_minutes * 60.0 if reason == "time_limit" else Game.match_elapsed
	var result := Game.finish_match(reason)
	match_finished.emit(result)
	Audio.play_ui("match_end", -4.0)


func is_running() -> bool:
	return running and not finished


func stop() -> void:
	running = false
	if Game.score_changed.is_connected(_on_score_changed):
		Game.score_changed.disconnect(_on_score_changed)


func alpha_alive() -> int:
	var n := 0
	if player != null and player.is_alive:
		n += 1
	for bot in bots:
		if bot.team == CBTeam.ALPHA and bot.is_alive:
			n += 1
	return n


func bravo_alive() -> int:
	var n := 0
	for bot in bots:
		if bot.team == CBTeam.BRAVO and bot.is_alive:
			n += 1
	return n

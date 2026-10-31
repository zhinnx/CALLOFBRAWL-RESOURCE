## CALLOFBRAWL — game manager (autoload).
##
## Global match state: team scores, per-combatant statistics, kill feed, active
## match model, and the scene transitions between menu and match. The rules that
## *drive* the match (clock, win conditions) live in MatchManager; this node only
## owns state so any scene can read or write it safely.
extends Node

signal match_configured
signal match_started
signal score_changed(alpha_score: int, bravo_score: int)
signal kill_feed(entry: Dictionary)
signal stats_changed
signal match_ended(result: Dictionary)

const MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const MATCH_SCENE := "res://scenes/gameplay/gameplay.tscn"

## Groups used by weapon hit detection.
const GROUP_HITBOX := "hitbox"
const GROUP_HEAD := "hitbox_head"
const GROUP_BODY := "hitbox_body"
const GROUP_COMBATANT := "combatant"
const GROUP_WORLD := "world_static"

var score_limit: int = 50
var match_minutes: float = 10.0
var respawn_delay: float = 3.0

var alpha_score: int = 0
var bravo_score: int = 0
var match_active: bool = false
var match_elapsed: float = 0.0

## combatant_id (String) -> {name, team, kills, deaths, headshots, is_bot, is_local}
var stats: Dictionary = {}
var kill_feed_entries: Array[Dictionary] = []
var final_result: Dictionary = {}

var local_player: Node = null
var local_combatant_id: String = "player"
var last_match_summary: Dictionary = {}


## Read the tunables from the settings file and reset all match state.
func configure_match() -> void:
	score_limit = maxi(5, Settings.get_int("score_limit"))
	match_minutes = maxf(1.0, Settings.get_float("match_minutes"))
	respawn_delay = maxf(0.0, Settings.get_float("respawn_delay"))
	reset_match()


func reset_match() -> void:
	alpha_score = 0
	bravo_score = 0
	match_active = false
	match_elapsed = 0.0
	stats.clear()
	kill_feed_entries.clear()
	final_result = {}
	match_configured.emit()


func begin_match() -> void:
	match_active = true
	match_started.emit()
	score_changed.emit(alpha_score, bravo_score)


# ---------------------------------------------------------------- combatants
func register_combatant(id: String, display_name: String, team: int, is_bot: bool, is_local: bool) -> void:
	stats[id] = {
		"id": id,
		"name": display_name,
		"team": team,
		"kills": 0,
		"deaths": 0,
		"headshots": 0,
		"is_bot": is_bot,
		"is_local": is_local,
	}
	stats_changed.emit()


func unregister_combatant(id: String) -> void:
	stats.erase(id)
	stats_changed.emit()


func get_stat(id: String) -> Dictionary:
	return stats.get(id, {})


func team_score(team: int) -> int:
	return alpha_score if team == CBTeam.ALPHA else bravo_score


## Called by WeaponController when a bullet connects with a combatant.
## Returns true if the hit was a legal (non-friendly-fire) elimination.
func report_damage_credit(attacker_id: String, victim_id: String, headshot: bool) -> void:
	var attacker := stats.get(attacker_id, {})
	if attacker.is_empty():
		return
	if headshot:
		attacker["headshots"] = int(attacker.get("headshots", 0)) + 1
	stats_changed.emit()


## Registers an elimination, updates both teams' scores, the kill feed and stats.
## `attacker_team` may be CBTeam.NONE for world deaths (which never score).
func report_elimination(attacker_id: String, attacker_name: String, attacker_team: int,
		victim_id: String, victim_name: String, victim_team: int, weapon: String,
		headshot: bool = false) -> bool:
	var legal := attacker_team != CBTeam.NONE and attacker_team != victim_team
	var victim_stat: Dictionary = stats.get(victim_id, {})
	if not victim_stat.is_empty():
		victim_stat["deaths"] = int(victim_stat.get("deaths", 0)) + 1
	if legal:
		var attacker_stat: Dictionary = stats.get(attacker_id, {})
		if not attacker_stat.is_empty():
			attacker_stat["kills"] = int(attacker_stat.get("kills", 0)) + 1
			if headshot:
				attacker_stat["headshots"] = int(attacker_stat.get("headshots", 0)) + 1
		if attacker_team == CBTeam.ALPHA:
			alpha_score += 1
		else:
			bravo_score += 1
		score_changed.emit(alpha_score, bravo_score)
	var entry := {
		"attacker": attacker_name,
		"attacker_team": attacker_team,
		"victim": victim_name,
		"victim_team": victim_team,
		"weapon": weapon,
		"headshot": headshot,
		"legal": legal,
		"world": attacker_team == CBTeam.NONE,
	}
	kill_feed_entries.append(entry)
	if kill_feed_entries.size() > 24:
		kill_feed_entries.pop_front()
	kill_feed.emit(entry)
	stats_changed.emit()
	return legal


func is_score_limit_reached() -> bool:
	return alpha_score >= score_limit or bravo_score >= score_limit


func finish_match(reason: String) -> Dictionary:
	match_active = false
	var winner := CBTeam.ALPHA
	if bravo_score > alpha_score:
		winner = CBTeam.BRAVO
	elif alpha_score == bravo_score:
		winner = CBTeam.NONE
	var mvp_id := ""
	var mvp_kills := -1
	for id in stats.keys():
		var s: Dictionary = stats[id]
		var score := int(s.get("kills", 0)) * 2 - int(s.get("deaths", 0))
		if score > mvp_kills:
			mvp_kills = score
			mvp_id = id
	var result := {
		"alpha_score": alpha_score,
		"bravo_score": bravo_score,
		"winner": winner,
		"reason": reason,
		"mvp_id": mvp_id,
		"stats": stats.duplicate(true),
		"elapsed": match_elapsed,
	}
	final_result = result
	last_match_summary = result
	match_ended.emit(result)
	return result


# ---------------------------------------------------------------- scene flow
func start_match() -> void:
	configure_match()
	get_tree().paused = false
	get_tree().change_scene_to_file(MATCH_SCENE)


func restart_match() -> void:
	start_match()


func go_to_menu() -> void:
	get_tree().paused = false
	Audio.stop_music()
	get_tree().change_scene_to_file(MENU_SCENE)


## Sort the scoreboard rows for the HUD.
func scoreboard_rows() -> Array:
	var rows: Array = stats.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("kills", 0)) != int(b.get("kills", 0)):
			return int(a.get("kills", 0)) > int(b.get("kills", 0))
		return int(a.get("deaths", 0)) < int(b.get("deaths", 0)))
	return rows

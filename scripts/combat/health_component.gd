## CALLOFBRAWL — health for a combatant.
##
## Kept deliberately small: authoritative health value, damage application with
## friendly-fire rejection, regeneration flag for bots, and signals so HUD / AI can
## react without polling.
class_name CBHealthComponent
extends Node

signal damaged(amount: float, attacker_id: String, headshot: bool, remaining: float)
signal died(attacker_id: String, headshot: bool)
signal healed(amount: float)
signal health_changed(current: float, maximum: float)

@export var max_health: float = 100.0
@export var team: int = CBTeam.NONE
## Owning combatant id, used for credit and friendly-fire checks.
var owner_id: String = ""
var owner_node: Node = null

var health: float = 100.0
var alive: bool = true


func _ready() -> void:
	health = max_health


func setup(id: String, owner_team: int, node: Node) -> void:
	owner_id = id
	team = owner_team
	owner_node = node
	health = max_health
	alive = true


func reset() -> void:
	health = max_health
	alive = true
	health_changed.emit(health, max_health)


func current_health() -> float:
	return health


func health_fraction() -> float:
	return clampf(health / maxf(1.0, max_health), 0.0, 1.0)


## Applies damage. Returns the health actually removed (0 when rejected/dead).
func apply_damage(amount: float, attacker_id: String, attacker_team: int, headshot: bool = false) -> float:
	if not alive or amount <= 0.0:
		return 0.0
	if attacker_team != CBTeam.NONE and CBTeam.is_friendly(attacker_team, team):
		return 0.0
	var before := health
	health = maxf(0.0, health - amount)
	var dealt := before - health
	damaged.emit(dealt, attacker_id, headshot, health)
	health_changed.emit(health, max_health)
	if health <= 0.0 and alive:
		alive = false
		died.emit(attacker_id, headshot)
	return dealt


func heal(amount: float) -> void:
	if not alive:
		return
	var before := health
	health = minf(max_health, health + amount)
	healed.emit(health - before)
	health_changed.emit(health, max_health)


func is_alive() -> bool:
	return alive

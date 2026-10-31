## CALLOFBRAWL — weapon definition resource.
##
## Every stat of a weapon is data, so the AK-47 can be re-tuned (or new weapons
## added) without touching code. See resources/weapons/ak47.tres.
class_name CBWeaponData
extends Resource

@export var display_name: String = "AK-47"
@export var short_name: String = "AK47"
@export_group("Ammunition")
@export var magazine_size: int = 30
@export var reserve_ammo: int = 120
@export var max_reserve_ammo: int = 210
@export_group("Ballistics")
@export var damage_body: float = 25.0
@export var damage_head: float = 100.0
@export var damage_limb: float = 18.0
@export var effective_range: float = 45.0
@export var max_range: float = 120.0
@export var range_falloff: float = 0.55
@export_group("Rate of fire")
@export var rounds_per_minute: float = 600.0
@export var automatic: bool = true
@export var burst_count: int = 0
@export_group("Accuracy")
@export var spread_standing: float = 1.2       # degrees, hip fire
@export var spread_moving: float = 3.4
@export var spread_ads: float = 0.35
@export var recoil_vertical: float = 0.85      # degrees per shot
@export var recoil_horizontal: float = 0.35
@export var recoil_recovery: float = 7.0       # degrees per second
@export var ads_zoom: float = 1.45
@export var ads_speed: float = 9.0
@export_group("Handling")
@export var reload_time: float = 2.45
@export var reload_empty_extra: float = 0.35
@export var equip_time: float = 0.55
@export_group("Presentation")
@export var muzzle_sound: String = "rifle"
@export_group("Bot tuning")
@export var bot_accuracy: float = 0.62         # 0..1, probability a shot is on target
@export var bot_damage_scale: float = 0.75     # bots hit softer than the player


func fire_interval() -> float:
	return 60.0 / maxf(1.0, rounds_per_minute)

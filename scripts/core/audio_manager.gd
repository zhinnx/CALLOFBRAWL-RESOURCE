## CALLOFBRAWL — audio manager (autoload).
##
## All sound effects in the project are *synthesised at runtime* from noise and
## sine oscillators (see scripts/core/sfx_synth.gd) so the repository ships no
## invented / mis-licensed audio files. Streams are generated once, cached, and
## replayed through a small pool of positional players.
##
## 3D playback uses a pool of AudioStreamPlayer3D nodes parented to this autoload;
## their `global_position` is assigned per shot, which is enough for stereo
## placement of gunfire and impacts without spawning nodes per event.
extends Node

const SfxSynth := preload("res://scripts/core/sfx_synth.gd")

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const POOL_SIZE := 20

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_index: int = 0
var _music: AudioStreamPlayer
var _ui_player: AudioStreamPlayer
var _music_stream: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_MUSIC, -6.0)
	_build_streams()
	_build_pool()
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	_music.stream = _music_stream
	add_child(_music)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = BUS_MASTER
	add_child(_ui_player)


# ---------------------------------------------------------------- buses
func _ensure_bus(bus_name: String, default_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)
	AudioServer.set_bus_volume_db(idx, default_db)


func apply_volumes(sound_volume: float, music_volume: float) -> void:
	var master := AudioServer.get_bus_index(BUS_MASTER)
	if master != -1:
		AudioServer.set_bus_mute(master, sound_volume <= 0.001)
		AudioServer.set_bus_volume_db(master, linear_to_db(clampf(sound_volume, 0.0001, 1.0)))
	var music := AudioServer.get_bus_index(BUS_MUSIC)
	if music != -1:
		AudioServer.set_bus_mute(music, music_volume <= 0.001)
		AudioServer.set_bus_volume_db(music, linear_to_db(clampf(music_volume, 0.0001, 1.0)))


# ---------------------------------------------------------------- synthesis
func _build_streams() -> void:
	_streams["rifle"] = SfxSynth.rifle_shot()
	_streams["rifle_distant"] = SfxSynth.rifle_shot(true)
	_streams["reload_out"] = SfxSynth.reload_mag_out()
	_streams["reload_in"] = SfxSynth.reload_mag_in()
	_streams["reload_bolt"] = SfxSynth.reload_bolt()
	_streams["empty"] = SfxSynth.empty_click()
	_streams["impact_concrete"] = SfxSynth.impact_concrete()
	_streams["impact_flesh"] = SfxSynth.impact_flesh()
	_streams["headshot"] = SfxSynth.headshot_ding()
	_streams["footstep"] = SfxSynth.footstep()
	_streams["land"] = SfxSynth.land()
	_streams["jump"] = SfxSynth.jump()
	_streams["elimination"] = SfxSynth.elimination()
	_streams["respawn"] = SfxSynth.respawn()
	_streams["hitmarker"] = SfxSynth.hitmarker()
	_streams["ui_click"] = SfxSynth.ui_click()
	_streams["ui_back"] = SfxSynth.ui_back()
	_streams["countdown"] = SfxSynth.countdown()
	_streams["match_end"] = SfxSynth.match_end()
	_streams["dryfire"] = SfxSynth.empty_click(0.8)
	# The 12 s ambience is 63 % of all synthesised samples: build it on the next idle
	# frame so the very first screen appears instantly on a low-end phone.
	_music_stream = null
	call_deferred("_build_music", null)


func _build_music() -> void:
	if _music_stream != null:
		return
	_music_stream = SfxSynth.menu_ambience()
	if _music != null:
		_music.stream = _music_stream


func _build_pool() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS_MASTER
		p.max_distance = 90.0
		p.unit_size = 12.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_pool.append(p)


# ---------------------------------------------------------------- playback
## Play a cached sound at a world position. `pitch_jitter` randomises the pitch a
## little so repeated gunfire does not sound mechanical.
func play_3d(sound: String, position: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.06,
		max_distance: float = 90.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var p = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = stream
	p.global_position = position
	p.volume_db = volume_db
	p.unit_size = 12.0
	p.max_distance = max_distance
	p.pitch_scale = clampf(1.0 + randf_range(-pitch_jitter, pitch_jitter), 0.5, 2.0)
	p.play()


## Non-positional playback (UI, local player's weapon detail, notifications).
func play_ui(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null or _ui_player == null:
		return
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.pitch_scale = pitch
	_ui_player.play()


## True when a synthesised stream exists for this sound name (used by the self test
## and by callers that want to stay silent instead of logging a missing sound).
func has_sound(sound: String) -> bool:
	return _streams.has(sound) and _streams[sound] != null


func play_music() -> void:
	if _music == null:
		return
	_build_music()
	if _music.stream != null and not _music.playing:
		_music.play()


func stop_music() -> void:
	if _music:
		_music.stop()


func music_playing() -> bool:
	return _music != null and _music.playing

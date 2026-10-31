## CALLOFBRAWL — procedural sound effects.
##
## Every effect is generated once at start-up into an AudioStreamWAV. Shapes are
## deliberately simple (filtered noise bursts, pitching sines, short envelopes)
## because they must be cheap to build on a low-end phone and small in memory.
##
## All functions return a 22050 Hz 16-bit mono AudioStreamWAV.
class_name SfxSynth
extends RefCounted

const RATE := 22050


static func _wav(samples: PackedFloat32Array, rate: int = RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v: float = clampf(samples[i], -1.0, 1.0)
		var s := int(v * 32767.0)
		data.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


static func _sizes(seconds: float, rate: int = RATE) -> int:
	return maxi(1, int(seconds * rate))


## One-pole low-pass helper; returns the filtered buffer.
static func _lowpass(buf: PackedFloat32Array, cutoff: float, rate: int = RATE) -> PackedFloat32Array:
	var alpha: float = clampf(1.0 - exp(-TAU * cutoff / rate), 0.0001, 1.0)
	var prev: float = 0.0
	for i in buf.size():
		prev += alpha * (buf[i] - prev)
		buf[i] = prev
	return buf


static func _highpass(buf: PackedFloat32Array, cutoff: float, rate: int = RATE) -> PackedFloat32Array:
	var alpha: float = clampf(1.0 - exp(-TAU * cutoff / rate), 0.0001, 1.0)
	var prev_in: float = 0.0
	var prev_out: float = 0.0
	for i in buf.size():
		prev_out = alpha * (prev_out + buf[i] - prev_in)
		prev_in = buf[i]
		buf[i] = prev_out
	return buf


static func _noise(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	return buf


# ---------------------------------------------------------------- weapons
## AK-47 shot: noise crack + low thump + a little filtered tail.
static func rifle_shot(distant: bool = false) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210 if not distant else 4242
	var dur := 0.34 if not distant else 0.5
	var n := _sizes(dur)
	var buf := _noise(n, rng)
	buf = _lowpass(buf, 5200.0 if not distant else 1900.0)
	if distant:
		buf = _highpass(buf, 220.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * (30.0 if not distant else 11.0))
		var attack: float = minf(1.0, t / 0.0015)
		var thump: float = sin(TAU * (95.0 - t * 90.0) * t) * exp(-t * 26.0) * 0.85
		var crack: float = buf[i] * 0.9 * env * attack
		out[i] = (thump + crack) * (0.85 if not distant else 0.55)
	return _wav(out)


static func reload_mag_out() -> AudioStreamWAV:
	return _mechanical(0.18, 2100.0, 0.55, 3311, 0.006)


static func reload_mag_in() -> AudioStreamWAV:
	return _mechanical(0.16, 2900.0, 0.7, 551, 0.004)


static func reload_bolt() -> AudioStreamWAV:
	return _mechanical(0.22, 1500.0, 0.6, 7717, 0.01)


static func _mechanical(dur: float, cutoff: float, gain: float, seed_value: int, attack: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := _sizes(dur)
	var buf := _lowpass(_noise(n, rng), cutoff)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 42.0) * minf(1.0, t / attack)
		var metal: float = sin(TAU * 1750.0 * t) * exp(-t * 60.0) * 0.35
		out[i] = (buf[i] * 0.8 + metal) * env * gain
	return _wav(out)


static func empty_click(pitch: float = 1.0) -> AudioStreamWAV:
	var n := _sizes(0.07)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 95.0)
		out[i] = (sin(TAU * 2600.0 * pitch * t) * 0.5 + sin(TAU * 3900.0 * pitch * t) * 0.2) * env * 0.5
	return _wav(out)


# ---------------------------------------------------------------- impacts
static func impact_concrete() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var n := _sizes(0.13)
	var buf := _highpass(_lowpass(_noise(n, rng), 6000.0), 900.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = buf[i] * exp(-t * 55.0) * 0.55
	return _wav(out)


static func impact_flesh() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8888
	var n := _sizes(0.16)
	var buf := _lowpass(_noise(n, rng), 850.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var thump: float = sin(TAU * 120.0 * t) * exp(-t * 40.0) * 0.35
		out[i] = (buf[i] * 0.5 + thump) * exp(-t * 26.0)
	return _wav(out)


static func headshot_ding() -> AudioStreamWAV:
	var n := _sizes(0.30)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 18.0)
		out[i] = (sin(TAU * 1480.0 * t) * 0.45 + sin(TAU * 2220.0 * t) * 0.18) * env
	return _wav(out)


static func hitmarker() -> AudioStreamWAV:
	var n := _sizes(0.05)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 2100.0 * t) * exp(-t * 120.0) * 0.25
	return _wav(out)


# ---------------------------------------------------------------- movement
static func footstep() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var n := _sizes(0.13)
	var buf := _lowpass(_highpass(_noise(n, rng), 180.0), 1400.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 48.0) * minf(1.0, t / 0.004)
		out[i] = buf[i] * env * 0.5
	return _wav(out)


static func jump() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var n := _sizes(0.16)
	var buf := _lowpass(_noise(n, rng), 900.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = buf[i] * exp(-t * 30.0) * minf(1.0, t / 0.01) * 0.35
	return _wav(out)


static func land() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2211
	var n := _sizes(0.22)
	var buf := _lowpass(_noise(n, rng), 700.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var thump: float = sin(TAU * 70.0 * t) * exp(-t * 26.0) * 0.4
		out[i] = (buf[i] * 0.5 + thump) * exp(-t * 20.0)
	return _wav(out)


# ---------------------------------------------------------------- match flow
static func elimination() -> AudioStreamWAV:
	var n := _sizes(0.45)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = exp(-t * 8.0)
		var f1: float = 660.0 * (1.0 - t * 0.5)
		out[i] = (sin(TAU * f1 * t) * 0.35 + sin(TAU * f1 * 1.5 * t) * 0.12) * env
	return _wav(out)


static func respawn() -> AudioStreamWAV:
	var n := _sizes(0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env: float = minf(1.0, t / 0.05) * exp(-t * 4.0)
		var f: float = 220.0 + 520.0 * minf(1.0, t / 0.4)
		out[i] = (sin(TAU * f * t) * 0.28 + sin(TAU * f * 2.0 * t) * 0.1) * env
	return _wav(out)


static func countdown() -> AudioStreamWAV:
	var n := _sizes(0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 880.0 * t) * exp(-t * 22.0) * 0.35
	return _wav(out)


static func match_end() -> AudioStreamWAV:
	var n := _sizes(1.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var notes := [440.0, 554.0, 659.0, 880.0]
	for i in n:
		var t := float(i) / RATE
		var v: float = 0.0
		for k in notes.size():
			var start: float = k * 0.16
			if t >= start:
				var lt: float = t - start
				v += sin(TAU * notes[k] * lt) * exp(-lt * 5.0) * 0.16
		out[i] = v
	return _wav(out)


# ---------------------------------------------------------------- ui
static func ui_click() -> AudioStreamWAV:
	var n := _sizes(0.05)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 1250.0 * t) * exp(-t * 90.0) * 0.3
	return _wav(out)


static func ui_back() -> AudioStreamWAV:
	var n := _sizes(0.08)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * (900.0 - t * 2500.0) * t) * exp(-t * 60.0) * 0.28
	return _wav(out)


# ---------------------------------------------------------------- music
## A slow, quiet menu ambience: two detuned pads with a gentle pulse.
static func menu_ambience() -> AudioStreamWAV:
	var dur := 12.0
	var n := _sizes(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var roots := [110.0, 146.83, 98.0, 130.81]
	var seg := dur / roots.size()
	for i in n:
		var t := float(i) / RATE
		var idx := mini(int(t / seg), roots.size() - 1)
		var lt: float = t - idx * seg
		var f: float = roots[idx]
		var fade: float = minf(1.0, lt / 1.2) * minf(1.0, (seg - lt) / 1.2)
		var pad: float = sin(TAU * f * t) * 0.5 + sin(TAU * f * 1.5 * t) * 0.22 + sin(TAU * f * 2.01 * t) * 0.12
		var pulse: float = 0.5 + 0.5 * sin(TAU * 0.5 * t)
		out[i] = pad * fade * pulse * 0.10
	return _wav(out)

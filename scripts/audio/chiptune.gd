extends RefCounted
## Little 8-bit sounds made in code: square-wave blips, noise bursts and a
## short jingle for each cartridge. Stand-ins until the real music and sound
## effects are made.

const RATE := 22050


## A WAV stream from mono samples in -1..1.
static func _stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Appends a note: `wave` is "square", "pulse" (thin square), "tri" or "noise".
static func _note(out: PackedFloat32Array, freq: float, seconds: float, wave: String = "square", volume: float = 0.35, slide: float = 0.0) -> void:
	var n := int(seconds * RATE)
	var phase := 0.0
	var noise := 0.0
	for i in range(n):
		var t := float(i) / n
		var f := freq * (1.0 + slide * t)
		phase = fmod(phase + f / RATE, 1.0)
		var v := 0.0
		match wave:
			"square":
				v = 1.0 if phase < 0.5 else -1.0
			"pulse":
				v = 1.0 if phase < 0.25 else -1.0
			"tri":
				v = 4.0 * absf(phase - 0.5) - 1.0
			"noise":
				if i % maxi(1, int(RATE / maxf(f, 1.0))) == 0:
					noise = randf() * 2.0 - 1.0
				v = noise
		# quick attack, then fade out: a plucky chip sound
		var env := minf(1.0, t * 40.0) * (1.0 - t) * (1.0 - t * 0.3)
		out.append(v * volume * env)


static func _rest(out: PackedFloat32Array, seconds: float) -> void:
	for i in range(int(seconds * RATE)):
		out.append(0.0)


## Frequency of a note `semitones` above A4.
static func _hz(semitones: int) -> float:
	return 440.0 * pow(2.0, semitones / 12.0)


## A tick for scrolling past a cartridge.
static func tick() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 1760.0, 0.035, "pulse", 0.25)
	return _stream(out)


## A swish as the cartridges slide.
static func swish() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 3000.0, 0.12, "noise", 0.18, -0.7)
	return _stream(out)


## The clunk of a cartridge going into the slot.
static func clunk() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 900.0, 0.05, "noise", 0.4, -0.8)
	_note(out, 110.0, 0.12, "square", 0.35, -0.5)
	return _stream(out)


## A happy little confirm.
static func select() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for st in [3, 7, 10, 15]:
		_note(out, _hz(st), 0.06, "square", 0.25)
	return _stream(out)


## Each cartridge's own few bars, made from its name so they're always the
## same: a bouncy square-wave tune over a triangle bass.
static func jingle(kind: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var scale: Array = [0, 2, 4, 7, 9, 12, 14, 16] if rng.randf() < 0.6 else [0, 3, 5, 7, 10, 12, 15, 17]
	var root := rng.randi_range(-5, 2)
	var beat := 0.11 + rng.randf() * 0.03
	var lead := PackedFloat32Array()
	var bass := PackedFloat32Array()
	var step := 0
	for bar in range(2):
		for i in range(8):
			var degree: int = scale[(step * 3 + rng.randi_range(0, 3)) % scale.size()]
			step += 1
			if i == 7 and bar == 1:
				degree = 12 # land on the octave
			if rng.randf() < 0.12 and i % 2 == 1:
				_rest(lead, beat)
			else:
				_note(lead, _hz(root + degree), beat, "square", 0.22)
			if i % 2 == 0:
				_note(bass, _hz(root - 24 + (0 if bar == 0 or i < 4 else 5)), beat * 2.0, "tri", 0.35)
	_note(lead, _hz(root + 12), beat * 3.0, "pulse", 0.2)
	_rest(bass, beat * 3.0)
	var out := PackedFloat32Array()
	out.resize(maxi(lead.size(), bass.size()))
	for i in range(out.size()):
		out[i] = (lead[i] if i < lead.size() else 0.0) + (bass[i] if i < bass.size() else 0.0)
	return _stream(out)


# ================================================================ the table

## A card flicked onto the felt.
static func flick() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 5000.0, 0.04, "noise", 0.22, -0.6)
	return _stream(out)


## A riffle shuffle and a quick deal.
static func shuffle() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for i in range(14):
		_note(out, 4000.0 + randf() * 2000.0, 0.025, "noise", 0.16, -0.3)
	_rest(out, 0.08)
	for i in range(3):
		_note(out, 2500.0, 0.05, "noise", 0.2, -0.7)
	return _stream(out)


## Cards slapped down: a meld, a book, a won trick.
static func slap() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 1800.0, 0.06, "noise", 0.35, -0.85)
	_note(out, 140.0, 0.06, "square", 0.15, -0.4)
	return _stream(out)


## Using an item: a bright little zap.
static func item() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, _hz(12), 0.05, "pulse", 0.2, 0.5)
	_note(out, _hz(19), 0.08, "pulse", 0.2, 0.3)
	return _stream(out)


static func heal() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for st in [0, 4, 7, 12, 16]:
		_note(out, _hz(st + 3), 0.05, "tri", 0.3)
	return _stream(out)


static func hurt() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 220.0, 0.18, "square", 0.3, -0.7)
	return _stream(out)


# ================================================================ guns

## The shotgun's pump: shk-shk.
static func rack() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 1400.0, 0.06, "noise", 0.4, -0.5)
	_rest(out, 0.07)
	_note(out, 900.0, 0.08, "noise", 0.45, -0.6)
	_note(out, 90.0, 0.04, "square", 0.2)
	return _stream(out)


## BANG: a crunchy burst over a deep thump.
static func blast() -> AudioStreamWAV:
	var noise := PackedFloat32Array()
	_note(noise, 6000.0, 0.45, "noise", 0.9, -0.95)
	var thump := PackedFloat32Array()
	_note(thump, 70.0, 0.35, "square", 0.6, -0.6)
	var out := PackedFloat32Array()
	out.resize(noise.size())
	for i in range(out.size()):
		out[i] = noise[i] + (thump[i] if i < thump.size() else 0.0)
	return _stream(out)


## A dry click: an empty chamber, or a blank.
static func click() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	_note(out, 3000.0, 0.02, "noise", 0.5)
	_note(out, 600.0, 0.03, "square", 0.15)
	return _stream(out)


## The revolver's cylinder spinning.
static func spin() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for i in range(10):
		_note(out, 2500.0, 0.015, "noise", 0.3)
		_rest(out, 0.02 + i * 0.006)
	return _stream(out)


# ================================================================ moments

## Someone won the round.
static func win() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for st in [0, 4, 7]:
		_note(out, _hz(st), 0.09, "square", 0.25)
	_note(out, _hz(12), 0.3, "pulse", 0.25)
	return _stream(out)


## Somebody walks out: the match is over.
static func fanfare() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for st in [0, 0, 0, 4, 7, 4, 7]:
		_note(out, _hz(st - 5), 0.1, "square", 0.25)
	_note(out, _hz(7), 0.5, "square", 0.25)
	return _stream(out)


## The lamp's hum, looping quietly under everything.
static func hum() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	var n := RATE * 2
	for i in range(n):
		var t := float(i) / RATE
		out.append(sin(TAU * 60.0 * t) * 0.05 + sin(TAU * 120.0 * t) * 0.03 + (randf() - 0.5) * 0.01)
	var s := _stream(out)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s

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

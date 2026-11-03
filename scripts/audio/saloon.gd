extends RefCounted
## The background music: a slow swing jazz blues in E minor, played by a
## little late-night trio. A mellow piano takes the tune, an upright bass
## walks underneath, a guitar strums soft chords on every beat, and the
## drummer keeps it moving with brushes and a quiet ride cymbal. No singing:
## just something to swing to.
##
## The tune is a 12-bar minor blues, written out note by note below. The room
## plays it on the piano; each game plays the same tune with its own little
## twist (the tempo, and the piano, vibraphone, guitar or a soft muted horn
## taking the lead), so a new game only needs a line in VARIANTS.
##
## Rendering is slow in GDScript, so the tracks are made once by
## tools/make_music.gd and saved in res://music/. render() is what it calls.

const RATE := 16000
const ROOT := 64 # E4: everything below is in semitones above (or below) it

## Each bar's chord: one per bar, or [first half, second half].
## Em7 Em7 Em7 Em7 | Am7 Am7 Em7 Em7 | Cmaj7 B7 Em7 F#m7b5-B7
const EM7 := [0, 3, 7, 10]
const AM7 := [5, 8, 12, 15]
const CMAJ7 := [-4, 0, 3, 7]
const B7 := [-5, -1, 2, 5]
const FSHM7B5 := [2, 5, 8, 12]
const CHORDS := [
	[EM7], [EM7], [EM7], [EM7],
	[AM7], [AM7], [EM7], [EM7],
	[CMAJ7], [B7], [EM7], [FSHM7B5, B7],
]

## The walking bass: four notes a bar, semitones above E2.
const BASS := [
	[0, 3, 7, 5], [0, 3, 5, -1], [0, 3, 7, 10], [12, 10, 7, 4],
	[5, 8, 12, 8], [5, 8, 10, 11], [12, 10, 7, 3], [0, 3, 5, 7],
	[8, 12, 15, 12], [7, 11, 14, 11], [12, 10, 7, 5], [2, 5, 7, -1],
]

## The tune: each bar is a list of [eighth (0-7), semitones above E4,
## length in eighths]. Bluesy and laid back, with room to breathe.
const MELODY := [
	[[1, 7, 1], [2, 10, 1], [3, 12, 3], [6, 10, 1], [7, 7, 1]],
	[[0, 10, 2], [2, 7, 1], [3, 5, 1], [4, 3, 3]],
	[[1, 7, 1], [2, 10, 1], [3, 12, 2], [5, 15, 1], [6, 14, 1], [7, 12, 1]],
	[[0, 10, 3], [3, 6, 1], [4, 7, 4]],
	[[1, 12, 1], [2, 15, 1], [3, 17, 3], [6, 15, 1], [7, 12, 1]],
	[[0, 15, 2], [2, 12, 1], [3, 10, 1], [4, 8, 3]],
	[[1, 7, 1], [2, 10, 1], [3, 12, 3], [6, 10, 1], [7, 7, 1]],
	[[0, 5, 1], [1, 3, 1], [2, 0, 4]],
	[[0, 15, 2], [2, 19, 2], [4, 15, 1], [5, 12, 1], [6, 8, 2]],
	[[0, 11, 2], [2, 14, 1], [3, 17, 1], [4, 14, 1], [5, 11, 1], [6, 7, 2]],
	[[0, 12, 3], [3, 10, 1], [4, 7, 2], [6, 3, 1], [7, 5, 1]],
	[[0, 7, 1], [1, 6, 1], [2, 5, 1], [3, 3, 1], [4, 2, 2], [6, -1, 2]],
]

## The room's version, and each game's twist: tempo, who takes the lead,
## how lazy the swing is (0.5 straight, 0.67 a full triplet shuffle).
const VARIANTS := {
	"room": {"bpm": 84, "lead": "piano", "swing": 0.66},
	"rummy": {"bpm": 88, "lead": "piano", "swing": 0.66},
	"blackjack": {"bpm": 82, "lead": "vibes", "swing": 0.66},
	"gofish": {"bpm": 90, "lead": "guitar", "swing": 0.64},
	"cheat": {"bpm": 86, "lead": "horn", "swing": 0.66},
	"hearts": {"bpm": 76, "lead": "vibes", "swing": 0.67},
	"spades": {"bpm": 80, "lead": "horn", "swing": 0.66},
	"snap": {"bpm": 96, "lead": "guitar", "swing": 0.64},
	"president": {"bpm": 80, "lead": "piano", "swing": 0.67},
	"poker": {"bpm": 72, "lead": "horn", "swing": 0.67},
}


## One cycle of a tone, made of harmonics: [strength of the 1st, 2nd, ...].
static func _table(harmonics: Array) -> PackedFloat32Array:
	var n := 1024
	var t := PackedFloat32Array()
	t.resize(n)
	var peak := 0.0
	for i in range(n):
		var v := 0.0
		for h in range(harmonics.size()):
			v += float(harmonics[h]) * sin(TAU * (h + 1) * i / n)
		t[i] = v
		peak = maxf(peak, absf(v))
	for i in range(n):
		t[i] /= peak
	return t


static func _tables() -> Dictionary:
	return {
		"piano": _table([1.0, 0.42, 0.16, 0.08, 0.03]),
		"piano_soft": _table([1.0, 0.15, 0.03]),
		"bass": _table([1.0, 0.45, 0.12, 0.05]),
		"guitar": _table([1.0, 0.55, 0.3, 0.18, 0.08]),
		"vibes": _table([1.0, 0.0, 0.0, 0.18]),
		"horn": _table([1.0, 0.35, 0.5, 0.15, 0.25, 0.06, 0.08]),
	}


## Where an eighth-note slot falls, in seconds, swung.
static func _slot_time(bar: int, slot: float, beat: float, swing: float) -> float:
	var b := floorf(slot / 2.0)
	var off := slot - b * 2.0
	var within := off * swing if off <= 1.0 else swing + (off - 1.0) * (1.0 - swing)
	return (bar * 4.0 + b + within) * beat


## A pitched note into `buf`, wrapping round the end so the track loops.
static func _note(buf: PackedFloat32Array, tables: Dictionary, start: float, length: float, midi: float, kind: String, volume: float) -> void:
	var f := 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var total := buf.size()
	var bright: PackedFloat32Array = tables["piano"]
	var mellow: PackedFloat32Array = tables["piano_soft"]
	var tail := 0.3
	match kind:
		"bass":
			bright = tables["bass"]
			mellow = tables["bass"]
			tail = 0.08
		"guitar":
			bright = tables["guitar"]
			mellow = tables["piano_soft"]
			tail = 0.05
		"vibes":
			bright = tables["vibes"]
			mellow = tables["vibes"]
			tail = 0.6
		"horn":
			bright = tables["horn"]
			mellow = tables["piano_soft"]
			tail = 0.08
	var n := int((length + tail) * RATE)
	var s0 := int(start * RATE)
	var size := bright.size()
	var p1 := 0.0
	var p2 := 0.31
	for i in range(n):
		var t := float(i) / RATE
		var env := 0.0
		var ff := f
		match kind:
			"bass": # a round pluck that rings for the beat
				env = minf(1.0, t / 0.006) * exp(-t * 2.2)
			"guitar": # a soft, damped strum
				env = minf(1.0, t / 0.004) * exp(-t * 9.0)
			"vibes": # a mallet, a long ring, the vibrato motor turning
				env = minf(1.0, t / 0.003) * exp(-t * 1.1) * (0.82 + 0.18 * sin(TAU * 5.0 * t))
			"horn": # breathed in, held, a little vibrato as it goes
				env = minf(1.0, t / 0.06) * (0.9 - 0.15 * minf(1.0, t / 1.5))
				ff = f * (1.0 + 0.004 * sin(TAU * 5.0 * t) * minf(1.0, t / 0.4))
			_: # the piano
				env = minf(1.0, t / 0.004) * exp(-t * 1.7)
		if t > length:
			env *= exp(-(t - length) / (tail * 0.3))
		p1 = fmod(p1 + ff / RATE, 1.0)
		p2 = fmod(p2 + ff * 1.0009 / RATE, 1.0)
		var k1 := int(p1 * size)
		var k2 := int(p2 * size)
		var tone := clampf(env * 1.2, 0.0, 1.0) # struck harder, it sounds brighter
		var v := (lerpf(mellow[k1], bright[k1], tone) + lerpf(mellow[k2], bright[k2], tone)) * 0.5
		var j := (s0 + i) % total
		buf[j] += v * env * volume


## The drummer: brushes swished round the snare, a hi-hat chick on 2 and 4,
## and a quiet ride cymbal keeping the swing.
static func _drums(buf: PackedFloat32Array, bars: int, beat: float, swing: float, rng: RandomNumberGenerator) -> void:
	var total := buf.size()
	var low := 0.0 # a one-pole filter to soften the noise into a brush
	for bar in range(bars):
		for b in range(4):
			var at := (bar * 4.0 + b) * beat
			# the brush: a soft swish across the whole beat
			var n := int(beat * 0.95 * RATE)
			var s0 := int(at * RATE)
			for i in range(n):
				var t := float(i) / n
				var env := sin(PI * t) * (0.6 + 0.4 * (1.0 - t))
				low += (rng.randf_range(-1.0, 1.0) - low) * 0.18
				buf[(s0 + i) % total] += low * env * 0.05
			# the ride: ding, ding-a ding
			var hits := [at]
			if b == 1 or b == 3:
				hits.append(at + swing * beat)
			for h in hits:
				var m := int(0.45 * RATE)
				var r0 := int(h * RATE)
				for i in range(m):
					var tt := float(i) / RATE
					var e := exp(-tt * 9.0)
					var v := sin(TAU * 3150.0 * tt) * 0.4 + sin(TAU * 4720.0 * tt) * 0.3 + sin(TAU * 5930.0 * tt) * 0.2 + rng.randf_range(-1.0, 1.0) * 0.25
					buf[(r0 + i) % total] += v * e * 0.03
			# the hi-hat closing on 2 and 4
			if b == 1 or b == 3:
				var k := int(0.05 * RATE)
				for i in range(k):
					var e := exp(-float(i) / RATE * 70.0)
					buf[(s0 + i) % total] += rng.randf_range(-1.0, 1.0) * e * 0.05


## The whole track for `id` (a key of VARIANTS), as a looping sound.
static func render(id: String) -> AudioStreamWAV:
	var v: Dictionary = VARIANTS.get(id, VARIANTS["room"])
	var beat := 60.0 / float(v["bpm"])
	var swing := float(v["swing"])
	var lead: String = v["lead"]
	var bars := MELODY.size()
	var buf := PackedFloat32Array()
	buf.resize(int(bars * 4.0 * beat * RATE))
	var tables := _tables()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("shotgun party " + id) # a human touch, but the same every time
	var lead_vol: float = {"piano": 0.36, "vibes": 0.34, "guitar": 0.36, "horn": 0.22}.get(lead, 0.34)
	for bar in range(bars):
		# the walking bass
		for b in range(4):
			var swing_push := rng.randf_range(-0.008, 0.008)
			_note(buf, tables, (bar * 4.0 + b) * beat + swing_push, beat * 0.92, 40 + int(BASS[bar][b]), "bass", 0.42 if b % 2 == 0 else 0.36)
		# the guitar: a soft chord on every beat, a touch more on 2 and 4
		var chords: Array = CHORDS[bar]
		for b in range(4):
			var chord: Array = chords[0] if chords.size() == 1 or b < 2 else chords[1]
			for tone in chord:
				var m := 52 + int(tone)
				while m > 62:
					m -= 12
				while m < 50:
					m += 12
				_note(buf, tables, (bar * 4.0 + b) * beat + rng.randf_range(0.0, 0.012), beat * 0.35, m, "guitar", 0.07 if b % 2 == 0 else 0.09)
		# the tune
		for nt in MELODY[bar]:
			var at := _slot_time(bar, float(nt[0]), beat, swing) + rng.randf_range(-0.012, 0.018)
			var end := _slot_time(bar, float(nt[0]) + float(nt[2]), beat, swing)
			var pitch := ROOT + int(nt[1])
			var vel := lead_vol * rng.randf_range(0.85, 1.0)
			_note(buf, tables, at, (end - at) * 0.95, pitch, lead, vel)
			if lead == "guitar":
				_note(buf, tables, at, (end - at) * 0.95, pitch - 12, "guitar", vel * 0.6) # octaves, the jazz way
		# the piano comps a little behind the other leads, on the "and" of 2
		if lead != "piano":
			var chord: Array = chords[0]
			for tone in chord:
				_note(buf, tables, _slot_time(bar, 3.0, beat, swing), beat * 0.6, 60 + int(tone), "piano", 0.06)
	_drums(buf, bars, beat, swing, rng)
	# a soft limiter so it never clips
	var peak := 0.0
	for x in buf:
		peak = maxf(peak, absf(x))
	var gain := 0.85 / maxf(peak, 0.001)
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in range(buf.size()):
		data.encode_s16(i * 2, int(clampf(tanh(buf[i] * gain * 1.1) / tanh(1.1), -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = buf.size()
	return s

extends RefCounted
## The saloon: background music played on an old bar-room piano. One tune,
## "Shotgun Party", written out below: a honky-tonk melody over a stride
## left hand (a low bass note, then a chord, then the fifth, then the chord),
## swung like ragtime. Each game plays the same tune with its own little
## twist (its own key and tempo, sometimes a banjo or a whistle on the
## melody), so new games only need a line in VARIANTS.
##
## Rendering is slow in GDScript, so the tracks are made once by
## tools/make_music.gd and saved in res://music/. render() is what it calls.

const RATE := 16000
const SWING := 0.62 # the first eighth of each beat is longer: the bounce

## The chord of each bar (semitones above the key), and its bass root.
const CHORDS := [
	[0, 4, 7], [0, 4, 7], [5, 9, 12], [0, 4, 7],
	[7, 11, 14, 17], [7, 11, 14, 17], [0, 4, 7], [0, 4, 7],
	[0, 4, 7], [0, 4, 7, 10], [5, 9, 12], [5, 8, 12],
	[0, 4, 7], [7, 11, 14, 17], [0, 4, 7], [7, 11, 14, 17],
]
const ROOTS := [0, 0, 5, 0, 7, 7, 0, 0, 0, 0, 5, 5, 0, 7, 0, 7]

## The tune: each bar is a list of [eighth (0-7), semitones above the key's
## middle C, length in eighths].
const MELODY := [
	[[0, 4, 1], [1, 7, 1], [2, 9, 1], [3, 7, 2], [5, 4, 1], [6, 0, 2]],
	[[0, 2, 1], [1, 4, 1], [2, 7, 2], [4, 4, 1], [5, 2, 1], [6, 0, 2]],
	[[0, 5, 1], [1, 9, 1], [2, 12, 2], [4, 9, 1], [5, 5, 1], [6, 9, 2]],
	[[0, 7, 3], [3, 4, 1], [4, 0, 2], [7, -5, 1]],
	[[0, 5, 1], [1, 7, 1], [2, 9, 1], [3, 11, 2], [5, 14, 1], [6, 11, 2]],
	[[0, 9, 1], [1, 7, 1], [2, 5, 2], [4, 2, 1], [5, 5, 1], [6, 7, 2]],
	[[0, 4, 1], [1, 7, 1], [2, 12, 2], [4, 7, 1], [5, 4, 1], [6, 7, 2]],
	[[0, 12, 4], [4, 7, 1], [5, 9, 1], [6, 10, 2]],
	[[0, 4, 1], [1, 7, 1], [2, 9, 1], [3, 7, 2], [5, 4, 1], [6, 0, 2]],
	[[0, 4, 1], [1, 7, 1], [2, 10, 2], [4, 9, 1], [5, 7, 1], [6, 4, 2]],
	[[0, 5, 1], [1, 9, 1], [2, 12, 2], [4, 9, 1], [5, 5, 1], [6, 9, 2]],
	[[0, 9, 1], [1, 8, 1], [2, 9, 2], [4, 5, 1], [5, 2, 1], [6, 0, 2]],
	[[0, 4, 1], [1, 7, 1], [2, 12, 3], [5, 11, 1], [6, 9, 2]],
	[[0, 7, 2], [2, 5, 2], [4, 2, 2], [6, -1, 2]],
	[[0, 0, 2], [2, 4, 1], [3, 7, 1], [4, 12, 2], [6, 7, 2]],
	[[0, 5, 1], [1, 4, 1], [2, 2, 2], [4, 7, 2]],
]

## The room's tune, and each game's twist on it: key (semitones from C),
## tempo, what plays the melody, how hard it swings.
const VARIANTS := {
	"room": {"key": 0, "bpm": 112, "lead": "piano", "swing": SWING},
	"rummy": {"key": 2, "bpm": 118, "lead": "piano", "swing": SWING},
	"blackjack": {"key": 5, "bpm": 124, "lead": "banjo", "swing": 0.6},
	"gofish": {"key": 7, "bpm": 110, "lead": "whistle", "swing": 0.64},
	"cheat": {"key": -2, "bpm": 128, "lead": "banjo", "swing": 0.66},
	"hearts": {"key": 3, "bpm": 100, "lead": "piano", "swing": 0.58},
	"spades": {"key": -3, "bpm": 114, "lead": "whistle", "swing": 0.6},
	"snap": {"key": 4, "bpm": 140, "lead": "banjo", "swing": 0.62},
	"president": {"key": -4, "bpm": 106, "lead": "piano", "swing": 0.64},
	"poker": {"key": -5, "bpm": 92, "lead": "piano", "swing": 0.68},
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


## Where an eighth-note slot falls, in seconds, with the swing.
static func _slot_time(bar: int, slot: float, beat: float, swing: float) -> float:
	var b := floorf(slot / 2.0)
	var off := slot - b * 2.0
	var within := off * swing if off <= 1.0 else swing + (off - 1.0) * (1.0 - swing)
	return (bar * 4.0 + b + within) * beat


## A note into `buf`, wrapping round the end so the track loops cleanly.
## kind: "piano" (two strings a little out of tune: honky-tonk), "banjo"
## (a bright pluck) or "whistle" (a pure tone with vibrato).
static func _note(buf: PackedFloat32Array, tables: Dictionary, start: float, length: float, midi: float, kind: String, volume: float) -> void:
	var f := 440.0 * pow(2.0, (midi - 69.0) / 12.0)
	var total := buf.size()
	var bright: PackedFloat32Array = tables["bright"]
	var mellow: PackedFloat32Array = tables["mellow"]
	var tail := 0.18
	match kind:
		"banjo":
			bright = tables["banjo"]
			tail = 0.06
		"whistle":
			bright = tables["sine"]
			mellow = tables["sine"]
			tail = 0.07
	var n := int((length + tail) * RATE)
	var s0 := int(start * RATE)
	var detune := 1.0035 if kind == "piano" else 1.0012
	var p1 := 0.0
	var p2 := 0.37
	var size := bright.size()
	for i in range(n):
		var t := float(i) / RATE
		# the envelope: a quick strike, a decay, and a quick fade once let go
		var env := 0.0
		match kind:
			"whistle":
				env = minf(1.0, t / 0.03) * 0.85
			"banjo":
				env = minf(1.0, t / 0.002) * exp(-t * 7.0)
			_:
				env = minf(1.0, t / 0.004) * exp(-t * 2.4)
		if t > length:
			env *= exp(-(t - length) / (tail * 0.3))
		var ff := f
		if kind == "whistle":
			ff = f * (1.0 + 0.006 * sin(TAU * 5.5 * t) * minf(1.0, t / 0.25))
		p1 = fmod(p1 + ff / RATE, 1.0)
		p2 = fmod(p2 + ff * detune / RATE, 1.0)
		var k1 := int(p1 * size)
		var k2 := int(p2 * size)
		var brightness := clampf(env * 1.3, 0.0, 1.0) # louder notes sound brighter
		var v1 := lerpf(mellow[k1], bright[k1], brightness)
		var v2 := lerpf(mellow[k2], bright[k2], brightness)
		var j := (s0 + i) % total
		buf[j] += (v1 + v2) * 0.5 * env * volume


## The whole track for `id` (a key of VARIANTS), as a looping sound.
static func render(id: String) -> AudioStreamWAV:
	var v: Dictionary = VARIANTS.get(id, VARIANTS["room"])
	var key := int(v["key"])
	var beat := 60.0 / float(v["bpm"])
	var swing := float(v["swing"])
	var bars := MELODY.size()
	var buf := PackedFloat32Array()
	buf.resize(int(bars * 4.0 * beat * RATE))
	var tables := {
		"bright": _table([1.0, 0.62, 0.45, 0.32, 0.22, 0.14, 0.08]),
		"mellow": _table([1.0, 0.3, 0.1, 0.04]),
		"banjo": _table([1.0, 0.9, 0.75, 0.6, 0.5, 0.4, 0.3, 0.22, 0.15]),
		"sine": _table([1.0, 0.05]),
	}
	var lead: String = v["lead"]
	var lead_vol := 0.34 if lead == "piano" else (0.3 if lead == "banjo" else 0.24)
	for bar in range(bars):
		# the left hand: stride
		var root := 48 + key + int(ROOTS[bar])
		var chord: Array = CHORDS[bar]
		_note(buf, tables, bar * 4.0 * beat, beat * 0.9, root, "piano", 0.32)
		_note(buf, tables, (bar * 4.0 + 2.0) * beat, beat * 0.9, root + 7 - 12 if root + 7 > 55 else root + 7, "piano", 0.28)
		for b in [1, 3]:
			for tone in chord:
				var m := 60 + key + int(tone)
				while m > 66:
					m -= 12
				while m < 54:
					m += 12
				_note(buf, tables, (bar * 4.0 + b) * beat, beat * 0.45, m, "piano", 0.13)
		# the right hand: the tune
		for nt in MELODY[bar]:
			var at := _slot_time(bar, float(nt[0]), beat, swing)
			var end := _slot_time(bar, float(nt[0]) + float(nt[2]), beat, swing)
			var pitch := 72 + key + int(nt[1])
			_note(buf, tables, at, (end - at) * 0.92, pitch, lead, lead_vol)
			if lead == "piano":
				_note(buf, tables, at, (end - at) * 0.92, pitch - 12, "piano", lead_vol * 0.35) # an octave under, for body
	# a gentle limiter so it never clips
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

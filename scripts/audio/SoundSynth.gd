class_name SoundSynth
## The game's own sound identity, synthesised in code (no downloaded sounds).
##
## Brand palette: "sneaky thief" in D minor -- wooden marimba, pizzicato bass,
## soft wooden knocks and shakers. Every effect uses the same instruments and
## key so the game sounds like one coherent product.
##
## All functions are static and thread-safe (no scene access), so the long
## music loop can be rendered on a worker thread.

const RATE := 22050
## Bump when any sound design changes so cached renders are rebuilt.
const VERSION := 4
## Silent frames added before and after every sound. The mixer interpolates
## a few samples beyond the playback position; without padding that read can
## run past the end of the buffer (crashes on Android with strict memory checks).
const PAD_FRAMES := 256

const SFX_IDS: Array[String] = [
	"pop", "wobble", "click", "rumble", "sizzle", "roll", "creak", "tear",
	"win", "lose", "star", "thud", "swoosh",
]


static func build(id: String) -> AudioStreamWAV:
	match id:
		"pop": return _pop()
		"wobble": return _wobble()
		"click": return _click()
		"rumble": return _rumble()
		"sizzle": return _sizzle()
		"roll": return _roll()
		"creak": return _creak()
		"tear": return _tear()
		"win": return _win()
		"lose": return _lose()
		"star": return _star()
		"thud": return _thud()
		"swoosh": return _swoosh()
		"music": return _music()
	return null


# ------------------------------------------------------------- utilities --

static func midi(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Normalises and converts to a 16-bit mono AudioStreamWAV.
static func _to_stream(buf: PackedFloat32Array, peak: float, loop: bool) -> AudioStreamWAV:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	var gain := peak / m
	var bytes := PackedByteArray()
	bytes.resize((buf.size() + PAD_FRAMES * 2) * 2)  # resize() zero-fills = silent padding
	for i in buf.size():
		bytes.encode_s16((PAD_FRAMES + i) * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		# Loop only the real audio, never the padding.
		s.loop_begin = PAD_FRAMES
		s.loop_end = PAD_FRAMES + buf.size()
	return s


## Signature instrument: wooden marimba bar (fundamental + 3.9x and 9.2x partials).
static func marimba(buf: PackedFloat32Array, t0: float, freq: float, amp: float, decay: float = 6.0) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(1.2 * RATE), buf.size() - start)
	var w := TAU * freq / RATE
	for i in n:
		var t := float(i) / RATE
		var attack := minf(1.0, t * 600.0)
		var v := sin(w * i) * exp(-t * decay)
		v += 0.28 * sin(w * 3.93 * i) * exp(-t * decay * 3.5)
		v += 0.08 * sin(w * 9.2 * i) * exp(-t * decay * 9.0)
		buf[start + i] += v * amp * attack


## Pizzicato string bass.
static func pluck(buf: PackedFloat32Array, t0: float, freq: float, amp: float, dur: float = 0.5) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(dur * RATE), buf.size() - start)
	var w := TAU * freq / RATE
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 7.0) * minf(1.0, t * 400.0)
		buf[start + i] += (sin(w * i) + 0.45 * sin(2.0 * w * i) * exp(-t * 12.0) + 0.15 * sin(3.0 * w * i) * exp(-t * 20.0)) * env * amp


## Bright bell (inharmonic partials) for stars and rewards.
static func bell(buf: PackedFloat32Array, t0: float, freq: float, amp: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(1.5 * RATE), buf.size() - start)
	var w := TAU * freq / RATE
	for i in n:
		var t := float(i) / RATE
		var v := sin(w * i) * exp(-t * 3.0) + 0.5 * sin(w * 2.76 * i) * exp(-t * 5.0) + 0.25 * sin(w * 5.4 * i) * exp(-t * 9.0)
		buf[start + i] += v * amp * minf(1.0, t * 800.0)


## Filtered noise burst. lowpass in 0..1 (smaller = darker).
static func noise(buf: PackedFloat32Array, t0: float, dur: float, amp: float, lowpass: float,
		decay: float, attack: float = 0.002) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(dur * RATE), buf.size() - start)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += lowpass * (randf_range(-1.0, 1.0) - y)
		buf[start + i] += y * amp * exp(-t * decay) * minf(1.0, t / attack)


## Wooden knock: short pitched thump + click.
static func knock(buf: PackedFloat32Array, t0: float, freq: float, amp: float) -> void:
	var start := int(t0 * RATE)
	var n := mini(int(0.12 * RATE), buf.size() - start)
	for i in n:
		var t := float(i) / RATE
		var f := freq * (1.0 + 0.6 * exp(-t * 60.0))
		buf[start + i] += sin(TAU * f * t) * exp(-t * 45.0) * amp
	noise(buf, t0, 0.02, amp * 0.5, 0.6, 200.0)


# ------------------------------------------------------------------ sfx --

## Block pop: bubbly upward marimba blip with a wooden click.
static func _pop() -> AudioStreamWAV:
	var b := _buf(0.35)
	var n := b.size()
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 520.0 + 900.0 * (1.0 - exp(-t * 30.0))
		phase += TAU * f / RATE
		b[i] += sin(phase) * exp(-t * 16.0) * minf(1.0, t * 900.0)
	marimba(b, 0.0, midi(86), 0.35, 14.0)  # D6 sparkle on top
	noise(b, 0.0, 0.015, 0.4, 0.7, 300.0)
	return _to_stream(b, 0.8, false)


## Single block can't pop: two dull wooden knocks.
static func _wobble() -> AudioStreamWAV:
	var b := _buf(0.3)
	knock(b, 0.0, 190.0, 1.0)
	knock(b, 0.11, 160.0, 0.8)
	return _to_stream(b, 0.7, false)


## UI click: crisp wooden tick.
static func _click() -> AudioStreamWAV:
	var b := _buf(0.12)
	knock(b, 0.0, 900.0, 0.6)
	marimba(b, 0.0, midi(81), 0.25, 30.0)
	return _to_stream(b, 0.6, false)


## Rock rumble loop: dark gravel noise with random small stone hits.
static func _rumble() -> AudioStreamWAV:
	var b := _buf(2.0)
	noise(b, 0.0, 2.0, 0.5, 0.05, 0.0, 0.0001)
	for k in 40:
		knock(b, randf_range(0.0, 1.88), randf_range(110.0, 260.0), randf_range(0.15, 0.4))
	return _to_stream(b, 0.7, true)


## Lava sizzle loop: hissing high noise with bubbling crackles.
static func _sizzle() -> AudioStreamWAV:
	var b := _buf(2.0)
	var y := 0.0
	var prev := 0.0
	for i in b.size():
		var x := randf_range(-1.0, 1.0)
		y = x - prev  # crude high-pass
		prev = x
		b[i] += y * 0.18 * (0.75 + 0.25 * sin(TAU * 3.0 * float(i) / RATE))
	for k in 30:
		var t0 := randf_range(0.0, 1.9)
		var start := int(t0 * RATE)
		var f := randf_range(300.0, 700.0)
		for i in mini(int(0.05 * RATE), b.size() - start):
			var t := float(i) / RATE
			b[start + i] += sin(TAU * f * (1.0 + t * 8.0) * t) * exp(-t * 80.0) * 0.4
	return _to_stream(b, 0.55, true)


## Boulder roll loop: deep rumble pulsing like a heavy stone turning.
static func _roll() -> AudioStreamWAV:
	var b := _buf(1.5)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += 0.02 * (randf_range(-1.0, 1.0) - y)
		b[i] = y * (0.6 + 0.4 * sin(TAU * 4.0 * t)) + sin(TAU * 48.0 * t) * 0.08
	return _to_stream(b, 0.8, true)


## Plank creak: bowed wood with wobbling pitch.
static func _creak() -> AudioStreamWAV:
	var b := _buf(0.6)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 140.0 + 40.0 * sin(TAU * 7.0 * t) + 60.0 * t
		phase += TAU * f / RATE
		var saw := 2.0 * fmod(phase / TAU, 1.0) - 1.0
		var env := sin(PI * t / 0.6)
		b[i] = saw * env * (0.6 + 0.4 * randf())
	# Soften: running average low-pass.
	var y := 0.0
	for i in b.size():
		y += 0.25 * (b[i] - y)
		b[i] = y
	return _to_stream(b, 0.6, false)


## Cloth tear: a fast rip (noise chopped at increasing rate).
static func _tear() -> AudioStreamWAV:
	var b := _buf(0.5)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += 0.5 * (randf_range(-1.0, 1.0) - y)
		var chop := 0.5 + 0.5 * signf(sin(TAU * (40.0 + 160.0 * t) * t))
		var env := minf(1.0, t * 40.0) * exp(-t * 5.0)
		b[i] = y * chop * env
	return _to_stream(b, 0.75, false)


## Win jingle: the brand motif D-F-A-C-D on marimba, landing on a bell chord.
static func _win() -> AudioStreamWAV:
	var b := _buf(2.2)
	var notes := [62, 65, 69, 72, 74]
	for k in notes.size():
		marimba(b, k * 0.11, midi(notes[k]), 0.8)
	pluck(b, 0.0, midi(38), 0.7, 1.0)
	for n: int in [74, 77, 81]:
		bell(b, 0.6, midi(n), 0.35)
	pluck(b, 0.6, midi(50), 0.6, 1.2)
	return _to_stream(b, 0.85, false)


## Lose: sad descending "wah" in the same key + a soft thud.
static func _lose() -> AudioStreamWAV:
	var b := _buf(1.8)
	var notes := [69.0, 68.0, 67.0, 65.5]
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := mini(int(t / 0.32), notes.size() - 1)
		var local := t - k * 0.32
		var vib := 0.25 * sin(TAU * 6.0 * t) * minf(1.0, t)
		phase += TAU * midi(notes[k] - 12.0 + vib) / RATE
		var tone := sin(phase) + 0.5 * sin(2.0 * phase) + 0.25 * sin(3.0 * phase)
		var env := minf(1.0, local * 30.0) * (exp(-local * 3.0) if k < notes.size() - 1 else exp(-local * 1.6))
		b[i] = tone * env * 0.5
	knock(b, 0.0, 90.0, 0.8)
	return _to_stream(b, 0.8, false)


## Star awarded: bright bell ping.
static func _star() -> AudioStreamWAV:
	var b := _buf(1.2)
	bell(b, 0.0, midi(86), 0.8)
	marimba(b, 0.0, midi(98), 0.2, 10.0)
	return _to_stream(b, 0.75, false)


## Heavy impact (boulder landing, thief caught).
static func _thud() -> AudioStreamWAV:
	var b := _buf(0.5)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * (55.0 + 80.0 * exp(-t * 25.0)) * t) * exp(-t * 9.0)
	noise(b, 0.0, 0.2, 0.5, 0.08, 20.0)
	return _to_stream(b, 0.9, false)


## Popup whoosh.
static func _swoosh() -> AudioStreamWAV:
	var b := _buf(0.35)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cutoff := 0.02 + 0.3 * sin(PI * t / 0.35)
		y += cutoff * (randf_range(-1.0, 1.0) - y)
		b[i] = y * sin(PI * t / 0.35)
	return _to_stream(b, 0.5, false)


# ---------------------------------------------------------------- music --

## Looping "sneaky thief" theme: 8 bars, 100 BPM, D minor. Marimba melody,
## pizzicato walking bass, shaker on the off-beats, finger snaps on 2 and 4.
static func _music() -> AudioStreamWAV:
	var beat := 0.6
	var bars := 8
	var loop_len := int(bars * 4 * beat * RATE)
	# Render 1.2 s past the loop end; the overflow is folded back onto the start.
	var b := _buf(bars * 4 * beat + 1.2)
	var e := beat * 0.5  # eighth note
	# Bass roots per bar (Dm Dm Bb A | Dm Dm Gm A).
	var roots := [38, 38, 34, 33, 38, 38, 43, 33]
	for bar in bars:
		var t := bar * 4 * beat
		var r: int = roots[bar]
		pluck(b, t, midi(r), 0.55, 0.55)
		pluck(b, t + 2 * e, midi(r + 7), 0.35, 0.4)
		pluck(b, t + 4 * e, midi(r + 12), 0.45, 0.5)
		pluck(b, t + 6 * e, midi(r + 7 if bar % 2 == 0 else r + 10), 0.35, 0.4)
		for k in 8:
			if k % 2 == 1:
				noise(b, t + k * e, 0.06, 0.08, 0.9, 60.0)  # shaker
		noise(b, t + 2 * e, 0.05, 0.18, 0.5, 90.0)  # snap on 2
		noise(b, t + 6 * e, 0.05, 0.18, 0.5, 90.0)  # snap on 4
	# Melody: [bar, eighth, midi]. Tiptoeing staccato motif built on D-F-A-C.
	var melody := [
		[0, 0, 62], [0, 2, 65], [0, 3, 67], [0, 4, 69], [0, 6, 72],
		[1, 0, 69], [1, 2, 67], [1, 4, 65], [1, 5, 64], [1, 6, 62],
		[2, 0, 62], [2, 2, 65], [2, 3, 67], [2, 4, 70], [2, 6, 69],
		[3, 0, 67], [3, 2, 64], [3, 3, 61], [3, 4, 64], [3, 6, 69],
		[4, 0, 74], [4, 1, 72], [4, 2, 69], [4, 4, 72], [4, 6, 74],
		[5, 0, 77], [5, 2, 76], [5, 3, 74], [5, 4, 72], [5, 6, 69],
		[6, 0, 70], [6, 2, 67], [6, 3, 70], [6, 4, 74], [6, 6, 72],
		[7, 0, 69], [7, 2, 67], [7, 3, 64], [7, 4, 61], [7, 6, 62],
	]
	for m: Array in melody:
		var start := (int(m[0]) * 4) * beat + int(m[1]) * e
		marimba(b, start, midi(float(m[2])), 0.32, 7.0)
	# Seamless loop: ringing notes that run past the end continue at the start.
	for i in b.size() - loop_len:
		b[i] += b[loop_len + i]
	b.resize(loop_len)
	return _to_stream(b, 0.7, true)

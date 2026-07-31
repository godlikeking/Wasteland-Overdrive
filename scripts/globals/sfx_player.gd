extends Node
## Programmatic SFX autoload. Synthesises 5 short retro blips via
## AudioStreamGenerator and serves them from a small AudioStreamPlayer
## pool. No external .wav/.ogg files are required.
##
## Usage:
##   SfxPlayer.play("fire")     # 5 短音
##   SfxPlayer.play("hit")
##   SfxPlayer.play("kill")
##   SfxPlayer.play("xp")
##   SfxPlayer.play("levelup")

const POOL_SIZE: int = 8          # 同时发声通道数
const SAMPLE_RATE: int = 22050   # 22 kHz 足够短音，CPU 友好

# 5 个 sfx id → AudioStream
var _streams: Dictionary = {}
# 循环使用的 AudioStreamPlayer 池
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	add_to_group("sfx_player")
	_streams["fire"]    = _make_blip(880.0, 0.06, "square")
	_streams["hit"]     = _make_blip(220.0, 0.07, "square")
	_streams["kill"]    = _make_sweep(440.0, 110.0, 0.18, "square")
	_streams["xp"]      = _make_blip(1320.0, 0.05, "sine")
	_streams["levelup"] = _make_arpeggio([523.0, 659.0, 784.0, 1047.0], 0.07, "square")
	# 预创建 POOL_SIZE 个 player
	for i in range(POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -4.0
		add_child(p)
		_pool.append(p)

## Play one of the 5 named SFX. Unknown ids are silently ignored.
func play(id: String) -> void:
	if not _streams.has(id):
		return
	if _pool.is_empty():
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[id]
	# Pitch slight variation to avoid robotic feel.
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()

# ---------------------------------------------------------------------------
# Synthesis helpers
# ---------------------------------------------------------------------------

## Single-tone blip. wave is one of: sine, square, triangle, saw.
func _make_blip(freq: float, dur: float, wave: String) -> AudioStream:
	return _synthesize(dur, func(t: float, n: int) -> float:
		return _wave(wave, freq, t)
	)

## Linear frequency sweep from `f0` to `f1` over `dur` seconds.
func _make_sweep(f0: float, f1: float, dur: float, wave: String) -> AudioStream:
	return _synthesize(dur, func(t: float, n: int) -> float:
		var k: float = t / dur
		var f: float = lerp(f0, f1, k)
		return _wave(wave, f, t)
	)

## Short arpeggio: list of frequencies, each held for `step` seconds.
func _make_arpeggio(freqs: Array, step: float, wave: String) -> AudioStream:
	var total: float = step * float(freqs.size())
	return _synthesize(total, func(t: float, n: int) -> float:
		var idx: int = clampi(int(t / step), 0, freqs.size() - 1)
		return _wave(wave, float(freqs[idx]), t)
	)

# ---------------------------------------------------------------------------
# Core synth
# ---------------------------------------------------------------------------

func _synthesize(dur: float, sample_fn: Callable) -> AudioStream:
	var frames: int = int(dur * SAMPLE_RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)   # 16-bit mono
	# 简单 ADSR 包络：attack 5ms, release 其余。短音不需 sustain。
	var attack: int = int(0.005 * SAMPLE_RATE)
	var release_start: int = max(attack, frames - int(0.03 * SAMPLE_RATE))
	for n in range(frames):
		var t: float = float(n) / float(SAMPLE_RATE)
		var s: float = sample_fn.call(t, n)
		# 包络
		var env: float = 1.0
		if n < attack:
			env = float(n) / float(max(1, attack))
		elif n > release_start:
			env = max(0.0, 1.0 - float(n - release_start) / float(max(1, frames - release_start)))
		s *= env * 0.4   # 总体降一档防止爆音
		var v: int = int(clampf(s, -1.0, 1.0) * 32767.0)
		# little-endian int16
		data[n * 2]     = v & 0xFF
		data[n * 2 + 1] = (v >> 8) & 0xFF
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

func _wave(kind: String, freq: float, t: float) -> float:
	var phase: float = fposmod(t * freq, 1.0)
	match kind:
		"sine":
			return sin(phase * TAU)
		"square":
			return 1.0 if phase < 0.5 else -1.0
		"triangle":
			return 1.0 - abs(phase * 2.0 - 1.0) * 2.0
		"saw":
			return phase * 2.0 - 1.0
		_:
			return sin(phase * TAU)

extends Node
## Plays the game's sounds. Four loops (wind, water, a flapping sail, rain)
## run all the time and are faded up and down to suit what is happening; a
## bell rings on arrival. The sound files are made by tools/make_sounds.py.

const SoundMix = preload("res://sim/sound_mix.gd")

const LOOPS: Array[String] = ["wind", "water", "flap", "rain"]
## How fast a sound fades, in loudness (0 to 1) a second.
const FADE_RATE := 1.5

var game
var muted := false
var _levels := {}
var _bell: AudioStreamPlayer


static func bus_name(sound: String) -> String:
	return "Sound " + sound


func setup(game_ref) -> void:
	game = game_ref
	for sound in LOOPS:
		var stream: AudioStreamWAV = load("res://audio/%s.wav" % sound)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
		# Each loop has its own volume control, so it can be faded on its own.
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name(sound))
		AudioServer.set_bus_send(index, "Master")
		AudioServer.set_bus_volume_db(index, SoundMix.SILENT_DB)
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = bus_name(sound)
		add_child(player)
		player.play()
		_levels[sound] = 0.0
	_bell = AudioStreamPlayer.new()
	_bell.stream = load("res://audio/bell.wav")
	add_child(_bell)


func _process(delta: float) -> void:
	var wanted := SoundMix.levels(game.is_sailing(), game.paused, game.wind_kn, game.ship.speed_kn,
		game.is_flapping(), game.squall_strength)
	for sound in LOOPS:
		var target: float = wanted[sound]
		var level: float = move_toward(_levels[sound], target, FADE_RATE * delta)
		_levels[sound] = level
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name(sound)), SoundMix.to_db(level))


## How loud a loop is right now, 0 to 1.
func level(sound: String) -> float:
	return _levels.get(sound, 0.0)


func set_muted(on: bool) -> void:
	muted = on
	AudioServer.set_bus_mute(0, on)


func ring_bell() -> void:
	_bell.play()

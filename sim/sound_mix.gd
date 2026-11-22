extends RefCounted
## How loud each sound should be, from 0 (silent) to 1, given what the ship
## is doing. The sounds themselves are played by game/sound.gd.

const PORT_WIND := 0.12
const SILENT_DB := -80.0


static func levels(sailing: bool, paused: bool, wind_kn: float, speed_kn: float, flapping: bool, squall: float) -> Dictionary:
	if paused:
		return {"wind": 0.0, "water": 0.0, "flap": 0.0, "rain": 0.0}
	if not sailing:
		# In port: a breeze in the rigging and nothing else.
		return {"wind": PORT_WIND, "water": 0.0, "flap": 0.0, "rain": 0.0}
	return {
		# A light air is a murmur; a squall is a roar.
		"wind": lerpf(0.15, 0.9, clampf((wind_kn - 4.0) / 20.0, 0.0, 1.0)),
		# Water along the hull grows with her speed.
		"water": pow(clampf(speed_kn / 8.0, 0.0, 1.0), 1.2) * 0.8,
		# A sail that is not drawing shakes, harder in more wind.
		"flap": 0.7 * clampf(wind_kn / 12.0, 0.4, 1.0) if flapping else 0.0,
		"rain": clampf(squall, 0.0, 1.0) * 0.8,
	}


## Loudness as the decibels the audio system wants.
static func to_db(level: float) -> float:
	return SILENT_DB if level <= 0.001 else linear_to_db(level)

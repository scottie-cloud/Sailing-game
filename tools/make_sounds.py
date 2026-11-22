#!/usr/bin/env python3
"""Makes the game's sounds from scratch and writes them to audio/.

    pip install numpy
    python3 tools/make_sounds.py audio

Every loop is built by shaping random noise in the frequency domain, which
makes it repeat without a click at the join. The same seed gives the same
files each time. Mono, 16-bit, 22,050 samples a second.
"""
import sys
import wave

import numpy as np

RATE = 22050


def shaped_noise(seconds, rng, gain):
    """Noise whose loudness at each frequency (Hz) is set by gain(f)."""
    count = int(RATE * seconds)
    spectrum = np.fft.rfft(rng.standard_normal(count))
    freqs = np.fft.rfftfreq(count, 1.0 / RATE)
    return np.fft.irfft(spectrum * gain(freqs), count)


def band(freqs, low, high, centre):
    """A hump of sound between low and high, loudest near centre."""
    safe = np.maximum(freqs, 1.0)
    shape = np.exp(-0.5 * (np.log(safe / centre) / 0.8) ** 2)
    return shape * (freqs > low) * (freqs < high)


def normalise(samples, peak):
    return samples / np.max(np.abs(samples)) * peak


def write(path, samples):
    data = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data.tobytes())
    rms = float(np.sqrt(np.mean(samples ** 2)))
    print("%s  %.2f s  peak %.2f  rms %.3f  join %.4f" % (path, len(samples) / RATE, np.max(np.abs(samples)), rms, abs(samples[0] - samples[-1])))


def wind(rng):
    """A steady moan with slow swells: 6 seconds."""
    seconds = 6.0
    t = np.arange(int(RATE * seconds)) / RATE
    low = shaped_noise(seconds, rng, lambda f: band(f, 60, 900, 260))
    high = shaped_noise(seconds, rng, lambda f: band(f, 500, 3500, 1300))
    swell = 0.7 + 0.3 * np.sin(2 * np.pi * t / 6.0) * np.sin(2 * np.pi * t / 3.0 + 1.0)
    whistle = 0.5 + 0.5 * np.sin(2 * np.pi * t / 2.0 + 0.6)
    return normalise(low * swell + 0.35 * high * swell * whistle, 0.8)


def water(rng):
    """Water rushing along the hull, surging as she meets each wave: 4 seconds."""
    seconds = 4.0
    t = np.arange(int(RATE * seconds)) / RATE
    wash = shaped_noise(seconds, rng, lambda f: band(f, 250, 6000, 1500))
    surge = 0.55 + 0.45 * np.sin(2 * np.pi * 0.75 * t) ** 2 + 0.15 * np.sin(2 * np.pi * 1.5 * t + 0.8)
    return normalise(wash * surge, 0.8)


def flap(rng):
    """Canvas shaking in the wind: quick dull thumps, 2 seconds."""
    seconds = 2.0
    count = int(RATE * seconds)
    cloth = shaped_noise(seconds, rng, lambda f: band(f, 70, 1400, 320))
    envelope = np.zeros(count)
    starts = np.sort((np.arange(13) + rng.uniform(-0.3, 0.3, 13)) / 13.0 * seconds) % seconds
    t = np.arange(count) / RATE
    for start, strength in zip(starts, rng.uniform(0.5, 1.0, 13)):
        # Wrap each thump round the end so the loop joins cleanly.
        since = (t - start) % seconds
        envelope += strength * np.exp(-since / 0.045)
    return normalise(cloth * envelope, 0.8)


def rain(rng):
    """Rain hissing on the water: 3 seconds."""
    seconds = 3.0
    t = np.arange(int(RATE * seconds)) / RATE
    hiss = shaped_noise(seconds, rng, lambda f: band(f, 1200, 10500, 5000))
    gust = 0.85 + 0.15 * np.sin(2 * np.pi * t / 3.0)
    return normalise(hiss * gust, 0.7)


def bell():
    """Two strokes on a ship's bell."""
    seconds = 2.2
    t = np.arange(int(RATE * seconds)) / RATE
    out = np.zeros_like(t)
    for start in (0.0, 0.42):
        since = np.maximum(t - start, 0.0)
        live = t >= start
        for ratio, level, decay in ((1.0, 1.0, 0.9), (2.76, 0.5, 0.5), (5.4, 0.3, 0.3), (8.93, 0.15, 0.18)):
            out += live * level * np.sin(2 * np.pi * 620.0 * ratio * since) * np.exp(-since / decay)
    out *= np.minimum(1.0, (seconds - t) / 0.2)
    return normalise(out, 0.7)


def main(folder):
    rng = np.random.default_rng(1851)
    write(folder + "/wind.wav", wind(rng))
    write(folder + "/water.wav", water(rng))
    write(folder + "/flap.wav", flap(rng))
    write(folder + "/rain.wav", rain(rng))
    write(folder + "/bell.wav", bell())


if __name__ == "__main__":
    main(sys.argv[1])

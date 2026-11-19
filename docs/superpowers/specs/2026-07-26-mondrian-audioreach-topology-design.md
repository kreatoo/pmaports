# Mondrian AudioReach Topology Design

## Goal

Provide the AudioReach topology required by the SM8450 APM driver so the Xiaomi Mondrian ALSA card registers and routes stereo multimedia playback through the tertiary TDM link to both AW88261 internal speaker amplifiers.

## Scope

This change covers internal speaker playback only. It does not add WCD938x headset playback, microphones, SoundWire WSA speakers, Bluetooth audio, or Android vendor audio services.

## Architecture

The existing DTS keeps `model = "Xiaomi-Mondrian"`, which makes `q6apm` request `/lib/firmware/qcom/sm8450/Xiaomi-Mondrian-tplg.bin`. A new topology source derives its multimedia stream graphs from Linaro's SM8450 HDK reference at commit `d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677` and replaces the reference WSA backend with a tertiary LPASS endpoint.

The endpoint uses `TERTIARY_TDM_RX_0` (DAI ID 56), tertiary LPASS interface index 2, SD0 data line, fixed-point S16_LE, 48 kHz, and two channels. The existing Mondrian sound card binds that backend to `aw88261_top` and `aw88261_bottom`; the topology describes the DSP graph, while DTS continues to describe the two physical amplifier codecs.

## Components

### Topology Source

`device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4` imports the public AudioReach macros and defines:

- `MultiMedia1` and `MultiMedia2` stereo playback stream subgraphs.
- One tertiary TDM playback device subgraph using the I2S sink module configured for the tertiary LPASS endpoint and DAI ID 56.
- Two playback mixers connecting each multimedia stream to the tertiary TDM device graph.
- Matching routes from each mixer to the stream logger endpoints.

The topology intentionally has one stereo TDM graph, not separate top and bottom amplifier graphs. The ALSA machine card fans its two stereo channels out to the two AW88261 codecs.

### Firmware Package

`firmware-xiaomi-mondrian` gains a `tplg` subpackage. During the package build, `m4` preprocesses `Xiaomi-Mondrian.m4` and `alsatplg` compiles the resulting configuration. The package installs the generated binary at:

```text
/lib/firmware/qcom/sm8450/Xiaomi-Mondrian-tplg.bin
```

`device-xiaomi-mondrian` depends on `firmware-xiaomi-mondrian-tplg` so the topology is present before `q6apm` probes.

## Data Flow

```text
MultiMedia1/2 PCM -> AudioReach stream logger -> tertiary TDM mixer
-> TERTIARY_TDM_RX_0 -> MI2S2 pins -> AW88261 top and bottom codecs -> speakers
```

## Failure Handling

- If topology preprocessing or compilation fails, APKBUILD fails; no partial topology package is produced.
- If the binary is absent or installed at a different path, `q6apm` fails with `-ENOENT`; the package file-list test prevents this regression.
- If the DSP rejects the TDM graph, ALSA card registration or playback fails and the device `dmesg` will identify the rejected graph/module. This is validated before adding unrelated routes or controls.

## Validation

1. Static package test verifies the M4 source, generated binary path, and device dependency.
2. Package build verifies `m4` and `alsatplg` produce `Xiaomi-Mondrian-tplg.bin`.
3. Device boot verifies no `tplg firmware loading ... failed` message.
4. `cat /proc/asound/cards` and `aplay -l` show the `Xiaomi-Mondrian` card.
5. `speaker-test -D default -c 2 -t wav` verifies stereo internal speaker playback.

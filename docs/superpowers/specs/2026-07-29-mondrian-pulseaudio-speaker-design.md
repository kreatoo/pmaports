# Mondrian PulseAudio Speaker Design

Date: 2026-07-29
Status: Approved for planning

## Goal

Expose Mondrian's proven `MultiMedia1` ALSA playback path as a named,
default PulseAudio speaker sink for immediate testing and as a persistent UCM
Speaker device after reboot and package installation.

## Current State

- ALSA card 0 is `Xiaomi-Mondrian`, with card ID `XiaomiMondrian` and driver
  identity `sm8450`.
- Playback PCM `hw:0,0` is `MultiMedia1` and accepts 48 kHz, S16_LE, stereo.
- Playback requires the mixer route
  `TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1`.
- `Top Speaker PCM Playback Volume` and
  `Bottom Speaker PCM Playback Volume` are attenuation controls: `0` is
  loudest and `720` is the -90 dB mute limit.
- PulseAudio 17 is the active Pulse-compatible server. It discovers
  `alsa_card.platform-sound`, but without UCM it leaves the card profile off
  and exposes only `auto_null`.
- PipeWire and WirePlumber are running separately but expose no audio device.
  They are outside this playback-only change.
- The Mondrian device package installs no UCM or sound-server configuration.

## Chosen Approach

Use two stages:

1. Create a reversible manual PulseAudio ALSA sink for immediate testing.
2. Add a minimal Mondrian UCM profile to the device package for persistent,
   standard card discovery.

The persistent implementation must not install a PulseAudio-specific
`module-alsa-sink` startup line. UCM is the established pmaports pattern and
can also be consumed by WirePlumber if the system later changes sound servers.

## Immediate Runtime Sink

The runtime test must:

1. Confirm no prior manual Mondrian sink is loaded.
2. Enable `TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1`.
3. Set both AW88261 attenuation controls to `600` (-75 dB additional
   attenuation before the ACF profile attenuation).
4. Load one `module-alsa-sink` for `hw:0,0` with:
   - a stable `mondrian_speakers` sink name;
   - user-visible description `Mondrian Speakers`;
   - S16_LE format;
   - 48 kHz rate;
   - two channels with front-left/front-right mapping;
   - timer scheduling disabled;
   - four 480-frame periods, matching the proven direct-ALSA probe geometry.
5. Set the resulting sink as PulseAudio's default output.
6. Keep PulseAudio software volume at `100%`; the fixed AW88261 `600`
   attenuation is the safety limit. PulseAudio `2%` was measured as
   `-101.95 dB` and made the otherwise clean path inaudible.

The module ID returned by `pactl load-module` must be retained. If sink loading
or playback setup fails, rollback must unload that module if present, restore
both AW88261 attenuation controls to `720`, and disable the TDM mixer route.

The runtime sink is temporary and disappears when PulseAudio restarts. It is
not a substitute for the UCM package.

## Persistent UCM Profile

Add two files under `device/testing/device-xiaomi-mondrian`:

- `alsa-ucm-conf/mondrian.conf`
- `alsa-ucm-conf/HiFi.conf`

`mondrian.conf` uses UCM Syntax 3 and exposes one `HiFi` use case that includes
`/Xiaomi/mondrian/HiFi.conf`.

`HiFi.conf` defines:

- one `SectionVerb` for HiFi playback;
- one `SectionDevice."Speaker"`;
- `PlaybackPCM "hw:${CardId},0"`;
- `PlaybackChannels 2`;
- a suitable playback priority so the internal speaker is selected when it is
  the only available output.

The HiFi enable sequence must:

1. Set both AW88261 attenuation controls to `600`.
2. Enable `TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1`.

The disable sequence must reverse this safely:

1. Set both AW88261 attenuation controls to `720`.
2. Disable `TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1`.

The UCM profile must not expose either hardware attenuation control as a
PulseAudio master mixer. Keep PulseAudio at `100%` for the verified baseline;
the hardware remains at the conservative fixed attenuation.

## Device Package Changes

Update `device/testing/device-xiaomi-mondrian/APKBUILD` to:

- increment `pkgrel` from 18 to 19;
- add `alsa-ucm-conf` to runtime dependencies;
- correct the stale exact topology dependency from
  `firmware-xiaomi-mondrian-tplg=1-r8` to the deployed and source-current
  `firmware-xiaomi-mondrian-tplg=1-r15`;
- add the two UCM files to `source` and `sha512sums`;
- install them under `/usr/share/alsa/ucm2/Xiaomi/mondrian/`;
- install a lookup symlink at
  `/usr/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Mondrian.conf` pointing to the
  board configuration.

No dedicated UCM provider package is needed for two board-local files.

## Activation And Default Selection

After installing the updated device package, restart the user's PulseAudio
server so `module-udev-detect` reloads `alsa_card.platform-sound` with UCM.
The card must expose an available HiFi output profile and a real speaker sink.

Select the HiFi profile if PulseAudio does not select it automatically, then
set the generated speaker sink as default. PulseAudio's existing
`module-default-device-restore` persists that default for later sessions.

The manual runtime module must be unloaded before validating UCM discovery so
it cannot mask a broken persistent profile or contend for `hw:0,0`.

## Verification

### Runtime Sink

- `pactl list short sinks` shows one named `mondrian_speakers` sink and no
  longer uses `auto_null` as default.
- `pactl get-default-sink` returns `mondrian_speakers`.
- Both AW88261 attenuation controls read `600` before playback.
- A short PulseAudio playback stream reaches the hardware at `100%` software
  volume, bounded by the fixed `600` hardware attenuation.
- Cleared dmesg shows both AW88261 devices starting without DSP, graph, TDM,
  ASoC, xrun, PLL, or amplifier-start errors.

### UCM Package

- UCM syntax/load checks resolve the Mondrian card and expose `HiFi` plus
  `Speaker`.
- The device package builds with correct source checksums and exact r15
  topology dependency.
- After package installation and PulseAudio restart, the card has an available
  HiFi output profile and a speaker sink without manually loading
  `module-alsa-sink`.
- The UCM speaker sink becomes the default output.
- Pulse playback again starts both amplifiers with a clean cleared dmesg.
- Disabling the profile sets both AW88261 attenuation controls to `720` and
  disables the MultiMedia1 TDM route.

## Failure Handling

- If the manual module cannot open `hw:0,0`, stop and inspect ownership and
  PulseAudio card/profile state; do not force access through a second sound
  server.
- If UCM does not load, retain the exact ALSA/UCM error and verify the
  `sm8450/Xiaomi-Mondrian.conf` lookup before changing profile contents.
- If PulseAudio opens the sink but hardware startup fails, stop playback,
  restore mute, and retain cleared dmesg. Do not modify DSP, lane, clock, or
  codec framing as part of this user-space integration.
- If playback is unexpectedly loud, immediately set both hardware controls to
  `720`, unload or suspend the sink, and disable the route.

## Non-Goals

- Microphone or capture support.
- Voice-call routing.
- Bluetooth policy changes.
- Replacing PulseAudio with PipeWire Pulse.
- Generic WirePlumber tuning.
- Kernel, topology, DSP ABI, clock, lane, or AW88261 driver changes.
- Resolving Task 4's physical top/bottom acoustic outlet naming.

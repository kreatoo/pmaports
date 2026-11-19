# Mondrian PulseAudio Speaker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose Mondrian's `MultiMedia1` ALSA path immediately as the default PulseAudio sink and persist it as a standard UCM Speaker device.

**Architecture:** First prove PulseAudio playback with a reversible manual `module-alsa-sink` using the already validated ALSA framing. Then package a board-local UCM HiFi/Speaker profile so PulseAudio's existing `module-udev-detect` creates the sink through `module-alsa-card`. Remove the manual module before persistent validation so it cannot mask UCM failures or contend for the PCM.

**Tech Stack:** PulseAudio 17, ALSA UCM Syntax 3, ALSA mixer controls, Alpine APKBUILD/pmaports, pmbootstrap, POSIX shell.

## Global Constraints

- Do not use git commands, worktrees, staging, commits, or branches.
- Use `/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap` for pmbootstrap operations.
- The user runs host package builds that may require sudo.
- Phone access is `user@172.16.42.1`; use `sudo` only after SSH.
- Use only ALSA card `Xiaomi-Mondrian`, PCM `hw:0,0`, 48 kHz, S16_LE, stereo.
- The required route is `TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1`.
- AW88261 attenuation `0` is loudest, `600` is the approved test level, and `720` is the mute limit.
- Keep PulseAudio at 100 percent software volume; the fixed AW88261 `600`
  attenuation is the safety limiter. PulseAudio `2%` is `-101.95 dB` and is
  inaudible on this path.
- Stop and restore both hardware controls to `720` if playback is unexpectedly loud or any DSP, graph, TDM, ASoC, xrun, PLL, or amplifier-start error appears.
- Keep this playback-only: no microphone, PipeWire migration, WirePlumber tuning, kernel, topology, DSP, lane, clock, or codec framing changes.
- The device package must depend exactly on `firmware-xiaomi-mondrian-tplg=1-r15`.

---

## File Structure

- `device/testing/device-xiaomi-mondrian/alsa-ucm-conf/mondrian.conf`: maps the ALSA card to the HiFi use case.
- `device/testing/device-xiaomi-mondrian/alsa-ucm-conf/HiFi.conf`: defines the Speaker PCM and safe route/attenuation sequences.
- `device/testing/device-xiaomi-mondrian/test-pulseaudio-speaker.sh`: focused source/package regression checks.
- `device/testing/device-xiaomi-mondrian/APKBUILD`: declares UCM dependency/sources, installs the files, and creates the `sm8450` lookup symlink.
- `/tmp/mondrian-pulse-module-id` on the phone: retains the temporary PulseAudio module ID for deterministic cleanup.
- `/tmp/speaker-pulse-manual-r20.log` and `/tmp/dmesg-speaker-pulse-manual-r20.log`: temporary-sink runtime evidence.
- `/tmp/speaker-pulse-ucm-r20.log` and `/tmp/dmesg-speaker-pulse-ucm-r20.log`: persistent UCM runtime evidence.

---

### Task 1: Prove A Reversible Manual PulseAudio Sink

**Files:**
- Create on phone: `/tmp/mondrian-pulse-module-id`
- Create on phone and retain locally: `/tmp/speaker-pulse-manual-r20.log`
- Create on phone and retain locally: `/tmp/dmesg-speaker-pulse-manual-r20.log`

**Interfaces:**
- Consumes: `hw:0,0`, the proven MultiMedia1 mixer route, PulseAudio card `alsa_card.platform-sound` with its profile currently off.
- Produces: named sink `mondrian_speakers`, its module ID, audible PulseAudio-path evidence, and a tested rollback sequence.

- [ ] **Step 1: Confirm the baseline has no real sink or stale manual module**

Run:

```sh
ssh user@172.16.42.1 'pactl list short sinks'
ssh user@172.16.42.1 'pactl list short modules'
ssh user@172.16.42.1 'pactl get-default-sink'
```

Expected:

- The only sink is `auto_null`.
- No `module-alsa-sink` instance names `mondrian_speakers`.
- The default sink is `auto_null`.

If `/tmp/mondrian-pulse-module-id` exists from an earlier attempt, inspect the
recorded ID and unload it before continuing:

```sh
ssh user@172.16.42.1 'test ! -s /tmp/mondrian-pulse-module-id || pactl unload-module "$(tr -d "\n" </tmp/mondrian-pulse-module-id)"'
```

- [ ] **Step 2: Establish the safe hardware state**

Run:

```sh
ssh user@172.16.42.1 'sudo dmesg -C'
ssh user@172.16.42.1 "amixer -c 0 cset name='Top Speaker PCM Playback Volume' 600"
ssh user@172.16.42.1 "amixer -c 0 cset name='Bottom Speaker PCM Playback Volume' 600"
ssh user@172.16.42.1 "amixer -c 0 cset name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' on"
```

Expected: dmesg is clear, both attenuation controls report `600/720`, and the
two-value topology control reports `on,off`, matching the established
single-value Qualcomm UCM route pattern.

- [ ] **Step 3: Load the fixed-format PulseAudio sink and retain its module ID**

Run:

```sh
ssh user@172.16.42.1 "pactl load-module module-alsa-sink device=hw:0,0 sink_name=mondrian_speakers \"sink_properties='device.description=\\\"Mondrian Speakers\\\"'\" format=s16le rate=48000 channels=2 channel_map=front-left,front-right tsched=0 fragments=4 fragment_size=1920 >/tmp/mondrian-pulse-module-id"
```

Expected: exit 0 and `/tmp/mondrian-pulse-module-id` contains one numeric
module ID.

If loading fails, immediately run the rollback from Step 7 and retain the
exact `pactl` error. Do not load a second sink or force access through
PipeWire.

- [ ] **Step 4: Make the hardware-limited manual sink default**

Run:

```sh
ssh user@172.16.42.1 'pactl set-default-sink mondrian_speakers'
ssh user@172.16.42.1 'pactl set-sink-volume mondrian_speakers 100%'
ssh user@172.16.42.1 'pactl set-sink-mute mondrian_speakers 0'
ssh user@172.16.42.1 'pactl get-default-sink'
ssh user@172.16.42.1 'pactl list short sinks'
```

Expected: `mondrian_speakers` is the default real sink at 48 kHz, S16_LE,
stereo; `auto_null` is no longer the active default.

- [ ] **Step 5: Run one bounded PulseAudio-path speaker test**

Run through the ALSA Pulse plugin rather than opening `hw:0,0` directly. Do not
clear dmesg here: module load opens the persistent PulseAudio sink and may have
already emitted the only AW88261 startup lines.

```sh
ssh user@172.16.42.1 'PULSE_SINK=mondrian_speakers timeout 6 speaker-test -D pulse -r 48000 -F S16_LE -c 2 -t sine -f 440 -l 1 >/tmp/speaker-pulse-manual-r20.log 2>&1'
ssh user@172.16.42.1 'sudo dmesg >/tmp/dmesg-speaker-pulse-manual-r20.log'
```

Expected: the user hears the bounded test at a quiet level, the speaker-test
log names both front channels, and both AW88261 devices report `start success`.

- [ ] **Step 6: Retain and inspect the runtime evidence**

Run:

```sh
scp user@172.16.42.1:/tmp/speaker-pulse-manual-r20.log /tmp/speaker-pulse-manual-r20.log
scp user@172.16.42.1:/tmp/dmesg-speaker-pulse-manual-r20.log /tmp/dmesg-speaker-pulse-manual-r20.log
rg -n 'aw88261 0-003(4|5): start success' /tmp/dmesg-speaker-pulse-manual-r20.log
! rg -q 'DSP returned error|Processing 0x|failed to configure TDM|Failed to open graph|Failed to set media format|Failed to prepare|Failed to start|ASoC error|underrun|xrun|check pll lock fail|device start failed' /tmp/dmesg-speaker-pulse-manual-r20.log
```

Expected: two start-success matches and exit 0 from the negative error check.
Task 1 will now prove rollback before reloading the successful sink for normal
app testing.

- [ ] **Step 7: Execute and verify the emergency rollback sequence**

Run the exact rollback used on any Task 1 failure or excessive volume:

```sh
ssh user@172.16.42.1 "amixer -c 0 cset name='Top Speaker PCM Playback Volume' 720"
ssh user@172.16.42.1 "amixer -c 0 cset name='Bottom Speaker PCM Playback Volume' 720"
ssh user@172.16.42.1 "amixer -c 0 cset name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' off"
ssh user@172.16.42.1 'test ! -s /tmp/mondrian-pulse-module-id || pactl unload-module "$(tr -d "\n" </tmp/mondrian-pulse-module-id)"'
ssh user@172.16.42.1 'rm -f /tmp/mondrian-pulse-module-id'
```

Expected on rollback: both hardware controls read `720`, the route is off,
and `mondrian_speakers` no longer appears in `pactl list short sinks`.

Verify those values explicitly:

```sh
ssh user@172.16.42.1 "amixer -c 0 cget name='Top Speaker PCM Playback Volume'"
ssh user@172.16.42.1 "amixer -c 0 cget name='Bottom Speaker PCM Playback Volume'"
ssh user@172.16.42.1 "amixer -c 0 cget name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1'"
ssh user@172.16.42.1 'pactl list short sinks'
```

- [ ] **Step 8: Reload the verified hardware-limited sink for application testing**

Repeat Steps 2 through 4 exactly, without another sine probe. Confirm both
hardware controls are `600`, the route is on, `mondrian_speakers` is default,
and its PulseAudio software volume is 100 percent. Leave this reloaded sink and
the refreshed numeric module ID in `/tmp/mondrian-pulse-module-id` for Task 3.

---

### Task 2: Package The Mondrian UCM Speaker Profile

**Files:**
- Create: `device/testing/device-xiaomi-mondrian/test-pulseaudio-speaker.sh`
- Create: `device/testing/device-xiaomi-mondrian/alsa-ucm-conf/mondrian.conf`
- Create: `device/testing/device-xiaomi-mondrian/alsa-ucm-conf/HiFi.conf`
- Modify: `device/testing/device-xiaomi-mondrian/APKBUILD`

**Interfaces:**
- Consumes: card lookup `sm8450/Xiaomi-Mondrian`, `hw:${CardId},0`, the three verified mixer controls, approved attenuation `600`, mute `720`.
- Produces: package release `device-xiaomi-mondrian-1-r19` with a UCM `HiFi` profile and `Speaker` device.

- [ ] **Step 1: Add the focused package regression test before production files**

Create `device/testing/device-xiaomi-mondrian/test-pulseaudio-speaker.sh`:

```sh
#!/bin/sh
set -eu

base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
apkbuild="$base/APKBUILD"
card="$base/alsa-ucm-conf/mondrian.conf"
hifi="$base/alsa-ucm-conf/HiFi.conf"

test -f "$card"
test -f "$hifi"

grep -Fq 'pkgrel=19' "$apkbuild"
grep -Fq 'alsa-ucm-conf' "$apkbuild"
grep -Fq 'firmware-xiaomi-mondrian-tplg=1-r15' "$apkbuild"
grep -Fq 'alsa-ucm-conf/HiFi.conf' "$apkbuild"
grep -Fq 'alsa-ucm-conf/mondrian.conf' "$apkbuild"
grep -Fq '/usr/share/alsa/ucm2/Xiaomi/mondrian/' "$apkbuild"
grep -Fq '/usr/share/alsa/ucm2/conf.d/sm8450' "$apkbuild"
grep -Fq '../../Xiaomi/mondrian/mondrian.conf' "$apkbuild"

grep -Fq 'Syntax 3' "$card"
grep -Fq 'SectionUseCase."HiFi"' "$card"
grep -Fq 'File "/Xiaomi/mondrian/HiFi.conf"' "$card"

grep -Fq 'Syntax 3' "$hifi"
grep -Fq 'SectionVerb' "$hifi"
grep -Fq 'SectionDevice."Speaker"' "$hifi"
grep -Fq 'PlaybackPCM "hw:${CardId},0"' "$hifi"
grep -Fq 'PlaybackChannels 2' "$hifi"
grep -Fq "name='Top Speaker PCM Playback Volume' 600" "$hifi"
grep -Fq "name='Bottom Speaker PCM Playback Volume' 600" "$hifi"
grep -Fq "name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 1" "$hifi"
grep -Fq "name='Top Speaker PCM Playback Volume' 720" "$hifi"
grep -Fq "name='Bottom Speaker PCM Playback Volume' 720" "$hifi"
grep -Fq "name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 0" "$hifi"
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
sh device/testing/device-xiaomi-mondrian/test-pulseaudio-speaker.sh
```

Expected: non-zero exit because
`device/testing/device-xiaomi-mondrian/alsa-ucm-conf/mondrian.conf` does not
exist yet.

- [ ] **Step 3: Add the UCM card configuration**

Create `device/testing/device-xiaomi-mondrian/alsa-ucm-conf/mondrian.conf`:

```text
Syntax 3

SectionUseCase."HiFi" {
	File "/Xiaomi/mondrian/HiFi.conf"
	Comment "HiFi quality Music."
}
```

- [ ] **Step 4: Add the UCM HiFi Speaker configuration**

Create `device/testing/device-xiaomi-mondrian/alsa-ucm-conf/HiFi.conf`:

```text
Syntax 3

SectionVerb {
	EnableSequence [
		cset "name='Top Speaker PCM Playback Volume' 600"
		cset "name='Bottom Speaker PCM Playback Volume' 600"
		cset "name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 1"
	]

	DisableSequence [
		cset "name='Top Speaker PCM Playback Volume' 720"
		cset "name='Bottom Speaker PCM Playback Volume' 720"
		cset "name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 0"
	]

	Value {
		TQ "HiFi"
	}
}

SectionDevice."Speaker" {
	Comment "Internal Speakers"

	Value {
		PlaybackPriority 200
		PlaybackPCM "hw:${CardId},0"
		PlaybackChannels 2
	}
}
```

- [ ] **Step 5: Update the device package metadata and sources**

In `device/testing/device-xiaomi-mondrian/APKBUILD`, make these exact metadata
changes:

```diff
-pkgrel=18
+pkgrel=19
```

Add `alsa-ucm-conf` to `depends` and correct the exact topology dependency:

```text
depends="
	alsa-ucm-conf
	linux-postmarketos-qcom-sm8450
	firmware-xiaomi-mondrian-gpu
	firmware-xiaomi-mondrian-audio
	firmware-xiaomi-mondrian-tplg=1-r15
```

Keep the remaining existing dependencies unchanged.

Add the UCM files to the beginning of `source`:

```text
source="
	alsa-ucm-conf/HiFi.conf
	alsa-ucm-conf/mondrian.conf
	deviceinfo
	pmos-usb-telnet.service
"
```

- [ ] **Step 6: Install the UCM files and lookup symlink from the package**

Append this focused block to `package()` after `devicepkg_package` and before
the unrelated USB telnet install:

```sh
	install -Dm644 "$srcdir"/mondrian.conf \
		"$pkgdir/usr/share/alsa/ucm2/Xiaomi/mondrian/mondrian.conf"
	install -Dm644 "$srcdir"/HiFi.conf \
		"$pkgdir/usr/share/alsa/ucm2/Xiaomi/mondrian/HiFi.conf"

	mkdir -p "$pkgdir/usr/share/alsa/ucm2/conf.d/sm8450"
	ln -s ../../Xiaomi/mondrian/mondrian.conf \
		"$pkgdir/usr/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Mondrian.conf"
```

- [ ] **Step 7: Refresh APKBUILD checksums**

Run:

```sh
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap checksum device-xiaomi-mondrian
```

Expected: `sha512sums` gains entries for `HiFi.conf` and `mondrian.conf` while
the existing source digests remain valid.

- [ ] **Step 8: Run focused tests and package syntax checks for GREEN**

Run:

```sh
sh -n device/testing/device-xiaomi-mondrian/test-pulseaudio-speaker.sh
(cd device/testing/device-xiaomi-mondrian && sh test-root-discovery.sh)
sh device/testing/device-xiaomi-mondrian/test-pulseaudio-speaker.sh
```

Expected: all commands exit 0 with no output.

- [ ] **Step 9: Review the package diff without git**

Read the complete `APKBUILD`, `mondrian.conf`, `HiFi.conf`, and test script.
Confirm:

- only playback is declared;
- enable uses `600`, then route on;
- disable uses `720`, then route off;
- no `PlaybackMixer` exposes AW88261 controls as a Pulse master;
- the only version coupling change is topology r8 to r15;
- no PulseAudio startup module or WirePlumber rule is installed.

---

### Task 3: Build, Deploy, And Verify Persistent UCM Discovery

**Files:**
- Build output: `/home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/device-xiaomi-mondrian-1-r19.apk`
- Installed on phone: `/usr/share/alsa/ucm2/Xiaomi/mondrian/mondrian.conf`
- Installed on phone: `/usr/share/alsa/ucm2/Xiaomi/mondrian/HiFi.conf`
- Installed on phone: `/usr/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Mondrian.conf`
- Create on phone and retain locally: `/tmp/speaker-pulse-ucm-r20.log`
- Create on phone and retain locally: `/tmp/dmesg-speaker-pulse-ucm-r20.log`

**Interfaces:**
- Consumes: the Task 2 r19 device package and the temporary Task 1 module ID.
- Produces: PulseAudio card profile `HiFi`, sink `alsa_output.platform-sound.HiFi__Speaker__sink`, default speaker output, verified disable/mute behavior.

- [ ] **Step 1: Have the user build the r19 device package**

The user runs on the host:

```sh
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build device-xiaomi-mondrian --force
```

Expected: build exit 0 and
`/home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/device-xiaomi-mondrian-1-r19.apk`
exists.

- [ ] **Step 2: Inspect package identity and contents before installation**

Run:

```sh
sha512sum /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/device-xiaomi-mondrian-1-r19.apk
tar -tf /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/device-xiaomi-mondrian-1-r19.apk
tar -xOf /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/device-xiaomi-mondrian-1-r19.apk .PKGINFO
```

Expected package contents include:

```text
usr/share/alsa/ucm2/Xiaomi/mondrian/mondrian.conf
usr/share/alsa/ucm2/Xiaomi/mondrian/HiFi.conf
usr/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Mondrian.conf
```

Expected `.PKGINFO` includes dependencies `alsa-ucm-conf` and exact
`firmware-xiaomi-mondrian-tplg=1-r15`.

- [ ] **Step 3: Remove the temporary sink and restore mute before UCM deployment**

Run:

```sh
ssh user@172.16.42.1 "amixer -c 0 cset name='Top Speaker PCM Playback Volume' 720"
ssh user@172.16.42.1 "amixer -c 0 cset name='Bottom Speaker PCM Playback Volume' 720"
ssh user@172.16.42.1 "amixer -c 0 cset name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' off"
ssh user@172.16.42.1 'test ! -s /tmp/mondrian-pulse-module-id || pactl unload-module "$(tr -d "\n" </tmp/mondrian-pulse-module-id)"'
ssh user@172.16.42.1 'rm -f /tmp/mondrian-pulse-module-id'
ssh user@172.16.42.1 'pactl list short sinks'
```

Expected: `mondrian_speakers` is absent and PulseAudio falls back to
`auto_null` before package installation.

- [ ] **Step 4: Install the r19 package on the phone**

Run:

```sh
scp /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/device-xiaomi-mondrian-1-r19.apk user@172.16.42.1:/tmp/
ssh user@172.16.42.1 'sudo apk add --allow-untrusted --force-overwrite /tmp/device-xiaomi-mondrian-1-r19.apk'
```

Expected: installation succeeds without downgrading the r15 topology package.

- [ ] **Step 5: Verify installed UCM files and syntax before restarting PulseAudio**

Run:

```sh
ssh user@172.16.42.1 'readlink /usr/share/alsa/ucm2/conf.d/sm8450/Xiaomi-Mondrian.conf'
ssh user@172.16.42.1 'alsaucm -c hw:0 dump text >/tmp/mondrian-ucm-dump.txt'
ssh user@172.16.42.1 'alsaucm -c hw:0 list _verbs'
```

Expected:

- symlink target is `../../Xiaomi/mondrian/mondrian.conf`;
- `alsaucm` exits 0;
- the verb list contains `HiFi`.

If UCM parsing fails, stop and retain `/tmp/mondrian-ucm-dump.txt` plus the
exact stderr. Do not restart PulseAudio until lookup/syntax is corrected.

- [ ] **Step 6: Restart PulseAudio and activate the UCM HiFi profile**

Run:

```sh
ssh user@172.16.42.1 'pulseaudio --kill'
ssh user@172.16.42.1 'pulseaudio --start'
ssh user@172.16.42.1 'pactl set-card-profile alsa_card.platform-sound HiFi'
ssh user@172.16.42.1 'pactl list cards'
ssh user@172.16.42.1 'pactl list short sinks'
```

Expected:

- card `alsa_card.platform-sound` exposes and activates profile `HiFi`;
- sink `alsa_output.platform-sound.HiFi__Speaker__sink` exists;
- no manual `module-alsa-sink` owns that sink.

- [ ] **Step 7: Set the UCM speaker sink as the hardware-limited default**

Run:

```sh
ssh user@172.16.42.1 'pactl set-default-sink alsa_output.platform-sound.HiFi__Speaker__sink'
ssh user@172.16.42.1 'pactl set-sink-volume alsa_output.platform-sound.HiFi__Speaker__sink 100%'
ssh user@172.16.42.1 'pactl set-sink-mute alsa_output.platform-sound.HiFi__Speaker__sink 0'
ssh user@172.16.42.1 'pactl get-default-sink'
ssh user@172.16.42.1 "amixer -c 0 cget name='Top Speaker PCM Playback Volume'"
ssh user@172.16.42.1 "amixer -c 0 cget name='Bottom Speaker PCM Playback Volume'"
ssh user@172.16.42.1 "amixer -c 0 cget name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1'"
```

Expected: the UCM speaker sink is default, both hardware controls are `600`,
and the route is on.

- [ ] **Step 8: Run one bounded persistent PulseAudio playback probe**

Run:

```sh
ssh user@172.16.42.1 'sudo dmesg -C'
ssh user@172.16.42.1 'PULSE_SINK=alsa_output.platform-sound.HiFi__Speaker__sink timeout 6 speaker-test -D pulse -r 48000 -F S16_LE -c 2 -t sine -f 440 -l 1 >/tmp/speaker-pulse-ucm-r20.log 2>&1'
ssh user@172.16.42.1 'sudo dmesg >/tmp/dmesg-speaker-pulse-ucm-r20.log'
scp user@172.16.42.1:/tmp/speaker-pulse-ucm-r20.log /tmp/speaker-pulse-ucm-r20.log
scp user@172.16.42.1:/tmp/dmesg-speaker-pulse-ucm-r20.log /tmp/dmesg-speaker-pulse-ucm-r20.log
```

Expected: audible quiet playback through the UCM sink.

- [ ] **Step 9: Verify the persistent probe logs**

Run:

```sh
rg -n 'aw88261 0-003(4|5): start success' /tmp/dmesg-speaker-pulse-ucm-r20.log
! rg -q 'DSP returned error|Processing 0x|failed to configure TDM|Failed to open graph|Failed to set media format|Failed to prepare|Failed to start|ASoC error|underrun|xrun|check pll lock fail|device start failed' /tmp/dmesg-speaker-pulse-ucm-r20.log
```

Expected: two start-success matches and exit 0 from the negative error check.

- [ ] **Step 10: Verify UCM disable safely remutes the hardware**

Run:

```sh
ssh user@172.16.42.1 'pactl set-card-profile alsa_card.platform-sound off'
ssh user@172.16.42.1 "amixer -c 0 cget name='Top Speaker PCM Playback Volume'"
ssh user@172.16.42.1 "amixer -c 0 cget name='Bottom Speaker PCM Playback Volume'"
ssh user@172.16.42.1 "amixer -c 0 cget name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1'"
```

Expected: both hardware controls are `720` and the route is off.

- [ ] **Step 11: Re-enable the final user-facing default state**

Run:

```sh
ssh user@172.16.42.1 'pactl set-card-profile alsa_card.platform-sound HiFi'
ssh user@172.16.42.1 'pactl set-default-sink alsa_output.platform-sound.HiFi__Speaker__sink'
ssh user@172.16.42.1 'pactl set-sink-volume alsa_output.platform-sound.HiFi__Speaker__sink 100%'
ssh user@172.16.42.1 'pactl get-default-sink'
ssh user@172.16.42.1 'pactl list short sinks'
```

Expected: the UCM Speaker sink is present and default at 100 percent software
volume, bounded by the `600` hardware attenuation and ready for normal
application testing. PulseAudio's existing
`module-default-device-restore` retains this default across later sessions.

- [ ] **Step 12: Request final review and retain residual risks**

Review the UCM files, package metadata, focused test, package contents, runtime
sink/card output, and both cleared logs. Retain these two known boundaries:

- physical top/bottom acoustic outlet naming remains unresolved from Task 4;
- the earlier detached-invocation no-clock anomaly is not treated as a normal
  PulseAudio failure unless it reproduces in these foreground probes.

No flash or reboot is required for this user-space package.

# Mondrian AudioReach Topology Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a reproducible SM8450 AudioReach topology that registers the `Xiaomi-Mondrian` ALSA card and routes stereo 48 kHz playback to the AW88261 tertiary-TDM speaker link.

**Architecture:** The kernel already describes the AW88261 pair and exposes `TERTIARY_TDM_RX_0` (DAI ID 56); the missing component is Q6 APM topology firmware. Package a small Mondrian-specific m4 topology with two standard multimedia playback streams and one tertiary LPASS endpoint, compile it using the pinned upstream AudioReach source, and install the result at the filename requested by the machine driver. The device package will depend on the topology subpackage so every device image includes it.

**Tech Stack:** Alpine APKBUILD, GNU m4, `alsatplg` from alsa-utils, Linaro AudioReach topology source at `d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677`, pmbootstrap, SSH, fastboot.

## Global Constraints

- Use `/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap`; do not use containers or `/workspace`.
- Preserve header v4 and flash only `boot_b`; retain the LineageOS `vendor_boot` image.
- PMOS rootfs is the nested GPT in `userdata` (`/dev/sda37`); never use or format `super`.
- Keep `model = "Xiaomi-Mondrian"`; the installed topology filename must be `/lib/firmware/qcom/sm8450/Xiaomi-Mondrian-tplg.bin`.
- Keep the initial topology limited to stereo `S16_LE`, 48 kHz speaker playback on `TERTIARY_TDM_RX_0` (DAI ID 56).
- Do not modify generated initramfs scripts, `/etc/fstab`, or add `pmos_root=...` to the kernel command line.
- Do not use git commands, create worktrees, stage files, or create commits.

---

## File Structure

- Create: `device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4` - source topology defining multimedia playback and the Mondrian tertiary-TDM backend.
- Modify: `device/testing/firmware-xiaomi-mondrian/APKBUILD` - pin and compile AudioReach, then package the topology firmware.
- Modify: `device/testing/device-xiaomi-mondrian/APKBUILD` - require the topology firmware on device images.
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh` - statically verify the topology source, packaging, and dependency contract.

### Task 1: Add the Topology Packaging Regression Test

**Files:**
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh`

**Interfaces:**
- Consumes: the existing `root` repository path and `kernel` sibling checkout path in the test script.
- Produces: a non-zero exit status when the topology source, firmware subpackage, exact installed path, or device dependency is missing.

- [ ] **Step 1: Add checks that should fail before the topology is packaged**

Append these lines after the current `speaker-playback-dai-link` assertion:

```sh
grep -q 'Xiaomi-Mondrian.m4' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q '\$pkgname-tplg' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q 'qcom/sm8450/Xiaomi-Mondrian-tplg.bin' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q 'TERTIARY_TDM_RX_0' "$root/device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4"
grep -q 'firmware-xiaomi-mondrian-tplg' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
```

- [ ] **Step 2: Run the regression test and confirm it fails**

Run: `sh device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh`

Expected: exit status `1` because `Xiaomi-Mondrian.m4` and the topology package references do not exist yet.

- [ ] **Step 3: Leave the assertions in place for the implementation tasks**

Do not weaken any existing AW88261, DTS, driver-format, or firmware assertions. The new assertions are intentionally file-content checks because the generated binary is produced only inside the APK build environment.

### Task 2: Define the Stereo Tertiary-TDM Topology

**Files:**
- Create: `device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4`

**Interfaces:**
- Consumes: AudioReach macros from the archive installed in the package build directory: `audioreach/audioreach.m4`, `audioreach/stream-subgraph.m4`, `audioreach/device-subgraph.m4`, `util/route.m4`, `util/mixer.m4`, and `audioreach/tokens.m4`.
- Produces: m4 input that expands into an `alsatplg` configuration containing `FRONTEND_DAI_MULTIMEDIA1`, `FRONTEND_DAI_MULTIMEDIA2`, and `TERTIARY_TDM_RX_0`.

- [ ] **Step 1: Create the topology source**

Create `device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4` with this complete content:

```m4
# SPDX-License-Identifier: BSD-3-Clause
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')

dnl Stereo playback streams exposed as MultiMedia1 and MultiMedia2.
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004001, 0x00004001, 0x00006001)
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA2,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004002, 0x00004002, 0x00006010)

dnl The Mondrian speaker amps receive a stereo stream through LPASS tertiary TDM.
DEVICE_SG_ADD(audioreach/subgraph-device-i2s-playback.m4, `TERTIARY_TDM_RX_0', TERTIARY_TDM_RX_0,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_TERTIARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,
	0x00004003, 0x00004003, 0x00006020, `TERTIARY_TDM_RX_0')

STREAM_DEVICE_PLAYBACK_MIXER(TERTIARY_TDM_RX_0, ``TERTIARY_TDM_RX_0'', ``MultiMedia1'', ``MultiMedia2'')
STREAM_DEVICE_PLAYBACK_ROUTE(TERTIARY_TDM_RX_0, ``TERTIARY_TDM_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'', ``MultiMedia2, stream1.logger1'')
```

- [ ] **Step 2: Verify the m4 source contains the intended endpoint contract**

Run: `grep -nE 'TERTIARY_TDM_RX_0|I2S_INTF_TYPE_TERTIARY|48000, 48000, 2, 2' device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4`

Expected: the command lists the DAI name in the device graph, the tertiary LPASS interface constant, and `48000, 48000, 2, 2` for both stream and backend graphs.

### Task 3: Build and Install the Topology Firmware Package

**Files:**
- Modify: `device/testing/firmware-xiaomi-mondrian/APKBUILD`

**Interfaces:**
- Consumes: `Xiaomi-Mondrian.m4` from Task 2 and the upstream archive checksum `267b36b227ecfbfe817c83a63c2ff5ad3e2beff185f20ac0e780fd242b89611da01efe2faaab501b575bae80d800413835735eb49624181c18cbc2647ab36929`.
- Produces: `firmware-xiaomi-mondrian-tplg`, which installs `/lib/firmware/qcom/sm8450/Xiaomi-Mondrian-tplg.bin`.

- [ ] **Step 1: Update the package metadata, sources, and build rule**

Make the following changes to `device/testing/firmware-xiaomi-mondrian/APKBUILD`:

```sh
pkgrel=4
```

```sh
subpackages="
	$pkgname-gpu
	$pkgname-audio
	$pkgname-tplg
"
```

```sh
makedepends="alsa-utils m4"
_audioreach_commit=d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677
_audioreach_dir="audioreach-topology-$_audioreach_commit"
source="
	a730_zap.mbn.zst
	aw882xx_acf.bin
	Xiaomi-Mondrian.m4
	$_audioreach_dir.tar.gz::https://github.com/linux-msm/audioreach-topology/archive/$_audioreach_commit.tar.gz
"
```

Insert this function before `package()`:

```sh
build() {
	m4 -I "$srcdir/$_audioreach_dir" "$srcdir/Xiaomi-Mondrian.m4" \
		> "$srcdir/Xiaomi-Mondrian-tplg.conf"
	alsatplg -c "$srcdir/Xiaomi-Mondrian-tplg.conf" \
		-o "$srcdir/Xiaomi-Mondrian-tplg.bin"
}
```

Insert this subpackage function after `audio()`:

```sh
tplg() {
	pkgdesc="Xiaomi POCO F5 Pro / Redmi K60 AudioReach topology firmware"

	install -Dm644 "$srcdir/Xiaomi-Mondrian-tplg.bin" \
		"$subpkgdir/lib/firmware/qcom/sm8450/Xiaomi-Mondrian-tplg.bin"
}
```

Add the following third entry to `sha512sums`, retaining the two existing entries unchanged:

```text
267b36b227ecfbfe817c83a63c2ff5ad3e2beff185f20ac0e780fd242b89611da01efe2faaab501b575bae80d800413835735eb49624181c18cbc2647ab36929  audioreach-topology-d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677.tar.gz
```

Do not add a checksum line for `Xiaomi-Mondrian.m4`; local package source files are not listed in `sha512sums` in this APKBUILD.

- [ ] **Step 2: Build only the firmware package**

Run: `/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build --force firmware-xiaomi-mondrian`

Expected: the build completes successfully and the log contains both `m4` and `alsatplg` without an m4 include error or an `alsatplg` parse error.

- [ ] **Step 3: Confirm the build contains the required installed path**

Run: `grep -q 'lib/firmware/qcom/sm8450/Xiaomi-Mondrian-tplg.bin' device/testing/firmware-xiaomi-mondrian/APKBUILD`

Expected: exit status `0`. Task 5 verifies the path in the installed device root filesystem after the documented pmbootstrap install and flash.

### Task 4: Require the Topology from the Mondrian Device Package

**Files:**
- Modify: `device/testing/device-xiaomi-mondrian/APKBUILD`

**Interfaces:**
- Consumes: the `firmware-xiaomi-mondrian-tplg` subpackage produced by Task 3.
- Produces: a device package that installs GPU firmware, AW88261 profile firmware, and required AudioReach topology firmware together.

- [ ] **Step 1: Add the firmware dependency and bump the package release**

Change these parts of `device/testing/device-xiaomi-mondrian/APKBUILD`:

```sh
pkgrel=12
```

Place the topology package directly after the existing audio package in `depends`:

```sh
	firmware-xiaomi-mondrian-audio
	firmware-xiaomi-mondrian-tplg
```

- [ ] **Step 2: Run the static audio integration regression test**

Run: `sh device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh`

Expected: exit status `0` with no output.

- [ ] **Step 3: Confirm the package release and dependency declarations**

Run:

```sh
grep -q '^pkgrel=12$' device/testing/device-xiaomi-mondrian/APKBUILD
grep -q 'firmware-xiaomi-mondrian-tplg' device/testing/device-xiaomi-mondrian/APKBUILD
```

Expected: both commands exit `0`.

### Task 5: Build, Flash, and Validate the Card and Speaker Path

**Files:**
- Modify: no additional source files.

**Interfaces:**
- Consumes: updated kernel package, `firmware-xiaomi-mondrian-tplg`, and `device-xiaomi-mondrian` from Tasks 1-4.
- Produces: a booted device that requests and successfully loads `qcom/sm8450/Xiaomi-Mondrian-tplg.bin`, registers an ALSA card, and exposes a tertiary-TDM playback route.

- [ ] **Step 1: Force-build all image inputs and export the images**

Run:

```sh
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build --force linux-postmarketos-qcom-sm8450 firmware-xiaomi-mondrian device-xiaomi-mondrian
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap install
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap export
```

Expected: all commands exit `0`, and `/tmp/postmarketOS-export/xiaomi-mondrian.img` plus `/tmp/postmarketOS-export/boot.img` exist.

- [ ] **Step 2: Flash the root filesystem and boot image without replacing vendor_boot**

Boot the phone to fastboot, then run:

```sh
fastboot flash userdata /tmp/postmarketOS-export/xiaomi-mondrian.img
fastboot flash boot_b /tmp/postmarketOS-export/boot.img
fastboot set_active b
fastboot reboot
```

Expected: each fastboot command reports `OKAY`; do not issue any `fastboot flash vendor_boot` command.

- [ ] **Step 3: Confirm topology firmware loading and ALSA-card registration**

After SSH is reachable at `192.168.1.203`, run:

```sh
ssh user@192.168.1.203 'dmesg | grep -E "Xiaomi-Mondrian-tplg|tplg firmware loading|snd-sc8280xp|aw88261"'
ssh user@192.168.1.203 'cat /proc/asound/cards; aplay -l'
```

Expected: the kernel log does not contain `Direct firmware load ... failed with error -2` or `tplg firmware loading ... failed`; `/proc/asound/cards` and `aplay -l` list the `Xiaomi-Mondrian` sound card and at least one playback device.

- [ ] **Step 4: Exercise the tertiary speaker backend**

Run:

```sh
ssh user@192.168.1.203 'amixer -c 0 controls | grep TERTIARY_TDM_RX_0'
ssh user@192.168.1.203 'speaker-test -D default -c 2 -r 48000 -F S16_LE -t wav -l 1'
```

Expected: the first command lists the `TERTIARY_TDM_RX_0 Audio Mixer` control. The second completes one stereo WAV loop without an ALSA device-open or route error; confirm audible output from both internal speakers.

## Self-Review

- Spec coverage: Task 2 implements the approved stereo 48 kHz tertiary-TDM graph; Task 3 pins and packages the exact topology filename; Task 4 makes it part of every Mondrian image; Task 5 verifies Q6 loading, ALSA registration, and physical playback. The plan does not modify `super`, `vendor_boot`, fstab, kernel command line, or initramfs scripts.
- Placeholder scan: no unspecified source, endpoint, checksum, filename, command, or verification condition remains.
- Interface consistency: the exact `Xiaomi-Mondrian-tplg.bin` name is used by the m4 source package, installed firmware path, regression test, device dependency, and boot-time verification.

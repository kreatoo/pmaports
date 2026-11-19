# Mondrian AW88261 Audio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register a Qualcomm SM8475 ALSA card and route its tertiary TDM playback link to Mondrian's two AW88261 internal speaker amplifiers.

**Architecture:** The board DTS declares the two verified AW88261 devices at I2C addresses `0x34` and `0x35`, configures the MI2S2/TDM pins, and adds a `qcom,sm8450-sndcard` playback link. The existing SC8280XP Qualcomm machine driver already binds that compatible, so it is extended only to initialize the tertiary-TDM clock, slot map, and codec format. A device firmware subpackage provides Xiaomi's signed `aw882xx_acf.bin` profile.

**Tech Stack:** Linux 7.1 ASoC, Qualcomm Q6 AFE, Device Tree, Alpine APKBUILD, pmbootstrap.

## Global Constraints

- Use `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/` as the editable kernel tree and regenerate `mondrian-linux.tar.gz` after source changes.
- Keep GPU firmware in `firmware-xiaomi-mondrian-gpu`; add a separate `firmware-xiaomi-mondrian-audio` subpackage.
- Install the vendor profile exactly as `/lib/firmware/aw882xx_acf.bin`.
- Target only internal speaker playback. Do not add headset, microphones, or Bluetooth audio in this change.
- Keep LineageOS `vendor_boot` untouched; use the existing host pmbootstrap installation and export workflow.

---

### Task 1: Add a Red Static Integration Check

**Files:**
- Create: `device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh`

**Interfaces:**
- Consumes: the kernel source DTS and ASoC driver paths below.
- Produces: a shell test that exits nonzero until the firmware package, SM8450 machine-driver binding, and Mondrian DTS speaker topology exist.

- [ ] **Step 1: Write the failing test**

```sh
#!/bin/sh
set -eu

root=$(git rev-parse --show-toplevel)
kernel="$root/../mondrian-linux"

grep -q 'cpu_dai->id == TERTIARY_TDM_RX_0' "$kernel/sound/soc/qcom/sc8280xp.c"
grep -q 'SND_SOC_DAIFMT_DSP_A' "$kernel/sound/soc/qcom/sc8280xp.c"
grep -q 'firmware-xiaomi-mondrian-audio' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
grep -q 'aw882xx_acf.bin' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q 'CONFIG_SND_SOC_AW88261=y' "$root/device/testing/linux-postmarketos-qcom-sm8450/config-postmarketos-qcom-sm8450.aarch64"
grep -q 'awinic,aw88261' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'aw882xx_acf.bin' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'speaker-playback-dai-link' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `sh device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh`

Expected: nonzero status because the SC8280XP machine driver has no tertiary-TDM path and the Mondrian DTS has no AW88261 nodes.

### Task 2: Package the Verified Awinic Profile

**Files:**
- Modify: `device/testing/firmware-xiaomi-mondrian/APKBUILD`
- Create: `device/testing/firmware-xiaomi-mondrian/aw882xx_acf.bin`
- Modify: `device/testing/device-xiaomi-mondrian/APKBUILD`

**Interfaces:**
- Consumes: Xiaomi's `aw882xx_acf.bin`, whose profile metadata identifies `AW88261` for board `M11A`.
- Produces: package `firmware-xiaomi-mondrian-audio`, providing `/lib/firmware/aw882xx_acf.bin` before the kernel probes either amplifier.

- [ ] **Step 1: Fetch the exact vendor profile**

Run:

```sh
wget -O device/testing/firmware-xiaomi-mondrian/aw882xx_acf.bin \
  https://raw.githubusercontent.com/TheMuppets/proprietary_vendor_xiaomi_mondrian/lineage-23.2/proprietary/vendor/firmware/aw882xx_acf.bin
sha512sum device/testing/firmware-xiaomi-mondrian/aw882xx_acf.bin
```

Expected: the file begins with `M11A` and contains `AW88261`; record the produced SHA512 in `APKBUILD`.

- [ ] **Step 2: Add the audio subpackage and package dependency**

```sh
subpackages="
	$pkgname-gpu
	$pkgname-audio
"

audio() {
	pkgdesc="Xiaomi POCO F5 Pro / Redmi K60 AW88261 speaker firmware"
	install -Dm644 "$srcdir"/aw882xx_acf.bin \
		"$subpkgdir"/lib/firmware/aw882xx_acf.bin
}
```

Add `aw882xx_acf.bin` to `source`, its SHA512 to `sha512sums`, and `firmware-xiaomi-mondrian-audio` to the device package `depends` block.

- [ ] **Step 3: Run package lint and confirm the installed path**

Run: `pmbootstrap checksum device-xiaomi-mondrian`

Expected: checksums are regenerated successfully. After building the package, `apk info -L firmware-xiaomi-mondrian-audio` lists `/lib/firmware/aw882xx_acf.bin`.

### Task 3: Enable AW88261 and Add SC8280XP TDM Machine Support

**Files:**
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/config-postmarketos-qcom-sm8450.aarch64`
- Modify: `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/sound/soc/qcom/sc8280xp.c`
- Modify: `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/sound/soc/codecs/aw88261.c`

**Interfaces:**
- Consumes: `qcom,sm8450-sndcard` from the Mondrian DTS and the two AW88261 DAI instances.
- Produces: a registered sound card whose `TERTIARY_TDM_RX_0` backend configures 48 kHz, eight 32-bit slots, and DSP_A framing for the speaker amplifiers.

- [ ] **Step 1: Enable the existing AW88261 codec driver**

Replace:

```text
# CONFIG_SND_SOC_AW88261 is not set
```

with:

```text
CONFIG_SND_SOC_AW88261=y
```

- [ ] **Step 2: Add tertiary-TDM backend setup**

In `sc8280xp.c`, retain the existing `qcom,sm8450-sndcard` match and add a `TERTIARY_TDM_RX_0` branch that sets `Q6AFE_LPASS_CLK_ID_TER_TDM_IBIT` to `12288000`, configures `SND_SOC_DAIFMT_DSP_A | SND_SOC_DAIFMT_NB_NF`, and applies the format to every codec DAI. Add a `hw_params` operation that sets eight 32-bit TDM slots and a two-channel playback map.

```c
case TERTIARY_TDM_RX_0:
	codec_dai_fmt |= SND_SOC_DAIFMT_NB_NF | SND_SOC_DAIFMT_DSP_A;
	snd_soc_dai_set_sysclk(cpu_dai, Q6AFE_LPASS_CLK_ID_TER_TDM_IBIT,
				12288000, SNDRV_PCM_STREAM_PLAYBACK);
	for_each_rtd_codec_dais(rtd, i, codec_dai)
		snd_soc_dai_set_fmt(codec_dai, codec_dai_fmt);
	break;
```

- [ ] **Step 3: Make AW88261 obey the DTS reset GPIO and DAI format**

Add a `reset` GPIO acquisition before regmap initialization and pulse it low then high with a 1 ms delay. Add `.set_fmt` and `.hw_params` DAI operations so the codec accepts the machine driver's TDM format and playback parameters. Do not add Pipa's hard-coded single-slot override because Mondrian has two channels.

- [ ] **Step 4: Compile the affected kernel objects**

Run:

```sh
make -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux ARCH=arm64 \
  sound/soc/qcom/sc8280xp.o sound/soc/codecs/aw88261.o
```

Expected: both objects compile without warnings or errors.

### Task 4: Declare Mondrian's Speaker Topology

**Files:**
- Modify: `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts`

**Interfaces:**
- Consumes: `snd-sc8280xp` binding, Q6 APM endpoints, AW88261 driver, and `aw882xx_acf.bin` firmware package.
- Produces: a `qcom,sm8450-sndcard` with an ALSA speaker playback backend using the exact board I2C and TDM wiring.

- [ ] **Step 1: Replace the stale TFA speaker declarations**

Remove the `tfa9873_l` and `tfa9873_r` nodes from `&i2c13`; they do not match Mondrian's verified hardware. Enable `&i2c15` and declare:

```dts
aw88261_top: speaker-amp@34 {
	compatible = "awinic,aw88261";
	reg = <0x34>;
	#sound-dai-cells = <0>;
	reset-gpios = <&tlmm 1 GPIO_ACTIVE_HIGH>;
	interrupts-extended = <&tlmm 88 IRQ_TYPE_LEVEL_LOW>;
	awinic,audio-channel = <0>;
	awinic,sync-flag;
	firmware-name = "aw882xx_acf.bin";
};

aw88261_bottom: speaker-amp@35 {
	compatible = "awinic,aw88261";
	reg = <0x35>;
	#sound-dai-cells = <0>;
	reset-gpios = <&tlmm 3 GPIO_ACTIVE_HIGH>;
	interrupts-extended = <&tlmm 63 IRQ_TYPE_LEVEL_LOW>;
	awinic,audio-channel = <1>;
	awinic,sync-flag;
	firmware-name = "aw882xx_acf.bin";
};
```

- [ ] **Step 2: Add the verified MI2S2 pin states and sound card**

Define active and sleep states for GPIOs 121 (SCK), 122 (DATA0), 123 (WS), and 124 (DATA1) using `mi2s2_*` functions. Add a root `sound` node with `compatible = "qcom,sm8450-sndcard"`, model `"Xiaomi-Mondrian"`, those pin states, and a `speaker-playback-dai-link` connecting `&q6apmbedai TERTIARY_TDM_RX_0`, `&aw88261_top`, `&aw88261_bottom`, and `&q6apm`.

- [ ] **Step 3: Build the Mondrian DTB**

Run:

```sh
make -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux ARCH=arm64 \
  qcom/sm8475-xiaomi-mondrian.dtb
```

Expected: `arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dtb` is produced without DTS warnings.

### Task 5: Regenerate Sources, Build, and Test on Hardware

**Files:**
- Modify: `mondrian-linux.tar.gz`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh`

**Interfaces:**
- Consumes: the complete source tree and package metadata from Tasks 1–4.
- Produces: a bootable pmOS image whose ALSA card has a speaker playback route.

- [ ] **Step 1: Regenerate the local kernel archive and checksum**

Run:

```sh
tar --exclude-vcs --exclude='*.o' --exclude='*.a' --exclude='*.cmd' \
  --exclude='*.dtb' --exclude='*.dtbo' --exclude='*.ko' --exclude='Image' \
  --exclude='vmlinux' --exclude='Module.symvers' --exclude='modules.*' \
  -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux \
  -czf /home/kreato/Sources/mondrian/mondrian/mondrian-linux.tar.gz .
ln -sfn ../../../../mondrian-linux.tar.gz \
  device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz
sha512sum /home/kreato/Sources/mondrian/mondrian/mondrian-linux.tar.gz
```

Replace the `linux-local.tar.gz` SHA512 in the kernel `APKBUILD` with the resulting digest.

- [ ] **Step 2: Verify the static integration test turns green**

Run: `sh device/testing/linux-postmarketos-qcom-sm8450/test-aw88261-audio.sh`

Expected: exit status 0.

- [ ] **Step 3: Build and export the image**

Run:

```sh
pmbootstrap build --force firmware-xiaomi-mondrian device-xiaomi-mondrian
pmbootstrap install --android-recovery-zip --no-fde
pmbootstrap export
```

Expected: all packages build and the export contains the updated `boot.img` and `xiaomi-mondrian.img`.

- [ ] **Step 4: Validate the installed hardware path**

After flashing the normal Mondrian `boot_b` and `userdata` images, run:

```sh
cat /proc/asound/cards
aplay -l
dmesg | grep -E 'aw88261|snd-sc8280xp|sm8450-sndcard'
speaker-test -D default -c 2 -t wav
```

Expected: an ALSA card appears; both AW88261 instances log their chip ID and profile load; `speaker-test` plays through the internal speakers.

# Mondrian Working Audio Reverse-Engineering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derive an evidence-backed difference between the known-good LineageOS Mondrian audio path and mainline r24, or prove that their software-visible AW88261 and tertiary-TDM behavior is equivalent.

**Architecture:** Analyze the exact manifest-pinned LineageOS source before using the supplied boot images as binary verification. Keep all downloaded and extracted artifacts in a private `/tmp/opencode` workspace, and write only the final evidence report into the repository. Stop at a decision gate; production code changes require a separate focused regression and implementation plan after a concrete mismatch is identified.

**Tech Stack:** GitHub raw/API access, Android boot image tools, AVB, LZ4/CPIO, DTB/DTBO, ARM64 binutils, Linux ASoC, Qualcomm PAL/AGM/AudioReach, AW882xx PID 2113.

## Global Constraints

- Do not use git commands, staging, commits, worktrees, or repository history commands.
- Do not modify any file under `/home/kreato/Downloads`.
- Copy and extract supplied images only under `/tmp/opencode/mondrian-audio-reference`.
- Do not flash `boot.img`, `vendor_boot.img`, `dtbo.img`, `userdata`, or any Android artifact.
- Do not change the phone, kernel, topology, ACF, UCM, or mixer state during this static investigation.
- Do not run any audible test without fresh explicit approval.
- Treat `aw882xx_acf.bin` and Mondrian ACDB as authoritative static configuration, but distinguish their payloads from runtime driver and PAL/AGM actions.
- Treat AW882xx `PID_2113` as AW88261 only when supported by chip ID `0x2113` and the exact PID register table.
- Do not implement a candidate fix until the final report identifies its source, execution order, expected observable effect, and a focused regression.
- Commit steps are intentionally omitted because the user explicitly prohibited git operations.

## File Structure

Pinned source revisions:

- `LineageOS/android_kernel_xiaomi_sm8450` at `e682ed2de56fd2841ef35741c4d0f03599ffd561`
- `LineageOS/android_kernel_xiaomi_sm8450-modules` at `ae45c06de3317b5ffcdf47bb9ccf35f7126d5933`
- `LineageOS/android_kernel_xiaomi_sm8450-devicetrees` at `895b75b6cc027e069960554c329e94b3f4b0f825`
- `LineageOS/android_device_xiaomi_mondrian` at `0bb28ea96d3adb7ff72064cc1428ad1520799ada`
- `LineageOS/android_device_xiaomi_sm8450-common` at `56a76e44de268ffacdee822f266708bcb4234ed6`
- `LineageOS/android_vendor_qcom_opensource_arpal-lx` at `a8c12069d5d2648ea02857eae5c9d9b9c26843fd`
- `LineageOS/android_vendor_qcom_opensource_agm` at `35c3491ff5566de4f60a64ad47e74fb39cd192e0`

- Create: `/tmp/opencode/mondrian-audio-reference/input/` - read-only copies of supplied images and manifest.
- Create: `/tmp/opencode/mondrian-audio-reference/source/` - manifest-pinned source snapshots fetched without git.
- Create: `/tmp/opencode/mondrian-audio-reference/unpacked/` - Android image components.
- Create: `/tmp/opencode/mondrian-audio-reference/ramdisks/` - checked CPIO listings and extracted ramdisks.
- Create: `/tmp/opencode/mondrian-audio-reference/dtbo/` - individual DTBO entries and decompiled DTS files.
- Create: `/tmp/opencode/mondrian-audio-reference/reports/` - generated hashes, inventories, symbol lists, and command output.
- Create: `docs/superpowers/reports/2026-08-11-mondrian-working-audio-comparison.md` - final persistent evidence and decision report.
- Read only: `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/sound/soc/codecs/aw88261.c` - deployed r24 codec behavior.
- Read only: `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/sound/soc/codecs/aw88261.h` - deployed r24 register definitions.
- Read only: `device/testing/firmware-xiaomi-mondrian/*.m4` - deployed r24 AudioReach TDM payload.
- Read only: `device/testing/firmware-xiaomi-mondrian/aw882xx_acf.bin` - deployed profile source.

---

### Task 1: Establish Immutable Artifact Custody

**Files:**
- Read: `/home/kreato/Downloads/boot.img`
- Read: `/home/kreato/Downloads/vendor_boot.img`
- Read: `/home/kreato/Downloads/dtbo.img`
- Read: `/home/kreato/Downloads/build-manifest.xml`
- Create: `/tmp/opencode/mondrian-audio-reference/input/*`
- Create: `/tmp/opencode/mondrian-audio-reference/reports/input-integrity.txt`

**Interfaces:**
- Consumes: the four supplied known-good LineageOS artifacts.
- Produces: immutable verified copies and exact SHA-256/AVB provenance used by every later task.

- [ ] **Step 1: Verify the approved scratch parent and create a private workspace**

Run:

```bash
test -d /tmp/opencode
test ! -e /tmp/opencode/mondrian-audio-reference
install -d -m 0700 \
  /tmp/opencode/mondrian-audio-reference/input \
  /tmp/opencode/mondrian-audio-reference/source \
  /tmp/opencode/mondrian-audio-reference/unpacked/boot \
  /tmp/opencode/mondrian-audio-reference/unpacked/vendor_boot \
  /tmp/opencode/mondrian-audio-reference/ramdisks/cpio \
  /tmp/opencode/mondrian-audio-reference/ramdisks/root/boot \
  /tmp/opencode/mondrian-audio-reference/ramdisks/root/vendor-platform \
  /tmp/opencode/mondrian-audio-reference/ramdisks/root/vendor-dlkm \
  /tmp/opencode/mondrian-audio-reference/dtbo/entries \
  /tmp/opencode/mondrian-audio-reference/dtbo/dts \
  /tmp/opencode/mondrian-audio-reference/reports
```

Expected: every directory is created with no pre-existing analysis state.

- [ ] **Step 2: Copy the inputs without changing the originals**

Run:

```bash
cp --reflink=auto --sparse=always /home/kreato/Downloads/boot.img \
  /tmp/opencode/mondrian-audio-reference/input/boot.img
cp --reflink=auto --sparse=always /home/kreato/Downloads/vendor_boot.img \
  /tmp/opencode/mondrian-audio-reference/input/vendor_boot.img
cp --reflink=auto --sparse=always /home/kreato/Downloads/dtbo.img \
  /tmp/opencode/mondrian-audio-reference/input/dtbo.img
cp --reflink=auto /home/kreato/Downloads/build-manifest.xml \
  /tmp/opencode/mondrian-audio-reference/input/build-manifest.xml
chmod 0400 /tmp/opencode/mondrian-audio-reference/input/*
```

Expected: four read-only files exist under `input/`; files under `/home/kreato/Downloads` retain their original metadata.

- [ ] **Step 3: Verify all known hashes**

Run:

```bash
sha256sum /tmp/opencode/mondrian-audio-reference/input/* \
  > /tmp/opencode/mondrian-audio-reference/reports/input-integrity.txt
```

Expected exact hashes:

```text
f7c4b1910c0180cb7fe6b7627af2562187523b65305a33095d8ac26a4962b9fc  boot.img
2ca22ffa71d45784eaa1ba95c277f70c685780d4ab88256afe1283da37abc83d  vendor_boot.img
07153952f424ff3446414d3162d376e8d05f17e556e48c4da43bc02adc428a71  dtbo.img
273c6bfbdee730727d0219f83c3721e6037f1611e8c8a9853f07229c04dbd3e1  build-manifest.xml
```

- [ ] **Step 4: Verify AVB descriptors before parsing**

Run:

```bash
/etc/profiles/per-user/kreato/bin/avbtool verify_image \
  --image /tmp/opencode/mondrian-audio-reference/input/boot.img
/etc/profiles/per-user/kreato/bin/avbtool verify_image \
  --image /tmp/opencode/mondrian-audio-reference/input/vendor_boot.img
/etc/profiles/per-user/kreato/bin/avbtool verify_image \
  --image /tmp/opencode/mondrian-audio-reference/input/dtbo.img
```

Expected: all three commands report successful descriptor verification.

- [ ] **Step 5: Verify manifest pins used by the design**

Run:

```bash
rg -n 'android_kernel_xiaomi_sm8450"|android_kernel_xiaomi_sm8450-modules|android_kernel_xiaomi_sm8450-devicetrees|android_device_xiaomi_mondrian|android_device_xiaomi_sm8450-common' \
  /tmp/opencode/mondrian-audio-reference/input/build-manifest.xml
```

Expected: revisions `e682ed2de56f...`, `ae45c06de331...`, `895b75b6cc02...`, `0bb28ea96d3a...`, and `56a76e44de26...` are present.

### Task 2: Retrieve the Exact Known-Good Sources Without Git

**Files:**
- Create: `/tmp/opencode/mondrian-audio-reference/source/kernel-modules/`
- Create: `/tmp/opencode/mondrian-audio-reference/source/devicetrees/`
- Create: `/tmp/opencode/mondrian-audio-reference/source/device-mondrian/`
- Create: `/tmp/opencode/mondrian-audio-reference/source/device-common/`
- Create: `/tmp/opencode/mondrian-audio-reference/source/pal/`
- Create: `/tmp/opencode/mondrian-audio-reference/source/agm/`
- Create: `/tmp/opencode/mondrian-audio-reference/reports/source-sha256.txt`

**Interfaces:**
- Consumes: exact revisions from Task 1.
- Produces: local text snapshots for source-level comparison, with no branch drift and no repository checkout.

- [ ] **Step 1: Fetch the complete pinned module and device repositories as immutable archives**

Run:

```bash
install -d -m 0700 \
  /tmp/opencode/mondrian-audio-reference/source/kernel-modules \
  /tmp/opencode/mondrian-audio-reference/source/devicetrees \
  /tmp/opencode/mondrian-audio-reference/source/device-mondrian \
  /tmp/opencode/mondrian-audio-reference/source/device-common \
  /tmp/opencode/mondrian-audio-reference/source/pal \
  /tmp/opencode/mondrian-audio-reference/source/agm
curl -fL \
  https://codeload.github.com/LineageOS/android_kernel_xiaomi_sm8450-modules/tar.gz/ae45c06de3317b5ffcdf47bb9ccf35f7126d5933 \
  -o /tmp/opencode/mondrian-audio-reference/source/kernel-modules.tar.gz
curl -fL \
  https://codeload.github.com/LineageOS/android_kernel_xiaomi_sm8450-devicetrees/tar.gz/895b75b6cc027e069960554c329e94b3f4b0f825 \
  -o /tmp/opencode/mondrian-audio-reference/source/devicetrees.tar.gz
curl -fL \
  https://codeload.github.com/LineageOS/android_device_xiaomi_mondrian/tar.gz/0bb28ea96d3adb7ff72064cc1428ad1520799ada \
  -o /tmp/opencode/mondrian-audio-reference/source/device-mondrian.tar.gz
curl -fL \
  https://codeload.github.com/LineageOS/android_device_xiaomi_sm8450-common/tar.gz/56a76e44de268ffacdee822f266708bcb4234ed6 \
  -o /tmp/opencode/mondrian-audio-reference/source/device-common.tar.gz
```

Expected: four non-empty gzip archives; no git metadata is created.

- [ ] **Step 2: Inspect archive paths before extraction**

Run:

```bash
tar -tzf /tmp/opencode/mondrian-audio-reference/source/kernel-modules.tar.gz \
  > /tmp/opencode/mondrian-audio-reference/reports/kernel-modules-archive.txt
tar -tzf /tmp/opencode/mondrian-audio-reference/source/devicetrees.tar.gz \
  > /tmp/opencode/mondrian-audio-reference/reports/devicetrees-archive.txt
tar -tzf /tmp/opencode/mondrian-audio-reference/source/device-mondrian.tar.gz \
  > /tmp/opencode/mondrian-audio-reference/reports/device-mondrian-archive.txt
tar -tzf /tmp/opencode/mondrian-audio-reference/source/device-common.tar.gz \
  > /tmp/opencode/mondrian-audio-reference/reports/device-common-archive.txt
if rg -n '(^|/)\.\.(/|$)|^/' \
  /tmp/opencode/mondrian-audio-reference/reports/*-archive.txt; then
  exit 1
fi
```

Expected: no archive entry begins with `/` or contains a `..` path component; the module archive lists `qcom/opensource/audio-kernel/asoc/codecs/aw882xx/`.

- [ ] **Step 3: Extract the source archives under their dedicated directories**

Run:

```bash
tar -xzf /tmp/opencode/mondrian-audio-reference/source/kernel-modules.tar.gz \
  --strip-components=1 \
  -C /tmp/opencode/mondrian-audio-reference/source/kernel-modules
tar -xzf /tmp/opencode/mondrian-audio-reference/source/devicetrees.tar.gz \
  --strip-components=1 \
  -C /tmp/opencode/mondrian-audio-reference/source/devicetrees
tar -xzf /tmp/opencode/mondrian-audio-reference/source/device-mondrian.tar.gz \
  --strip-components=1 \
  -C /tmp/opencode/mondrian-audio-reference/source/device-mondrian
tar -xzf /tmp/opencode/mondrian-audio-reference/source/device-common.tar.gz \
  --strip-components=1 \
  -C /tmp/opencode/mondrian-audio-reference/source/device-common
```

Expected: source directories contain no `.git/` and preserve the pinned source files.

- [ ] **Step 4: Fetch only the pinned PAL and AGM files needed to trace runtime configuration**

Run:

```bash
curl -fL \
  https://raw.githubusercontent.com/LineageOS/android_vendor_qcom_opensource_arpal-lx/a8c12069d5d2648ea02857eae5c9d9b9c26843fd/session/src/SessionAlsaUtils.cpp \
  -o /tmp/opencode/mondrian-audio-reference/source/pal/SessionAlsaUtils.cpp
curl -fL \
  https://raw.githubusercontent.com/LineageOS/android_vendor_qcom_opensource_arpal-lx/a8c12069d5d2648ea02857eae5c9d9b9c26843fd/device/src/Device.cpp \
  -o /tmp/opencode/mondrian-audio-reference/source/pal/Device.cpp
curl -fL \
  https://raw.githubusercontent.com/LineageOS/android_vendor_qcom_opensource_arpal-lx/a8c12069d5d2648ea02857eae5c9d9b9c26843fd/PalAudioRoute.h \
  -o /tmp/opencode/mondrian-audio-reference/source/pal/PalAudioRoute.h
curl -fL \
  https://raw.githubusercontent.com/LineageOS/android_vendor_qcom_opensource_agm/35c3491ff5566de4f60a64ad47e74fb39cd192e0/plugins/tinyalsa/src/agm_mixer_plugin.c \
  -o /tmp/opencode/mondrian-audio-reference/source/agm/agm_mixer_plugin.c
curl -fL \
  https://raw.githubusercontent.com/LineageOS/android_vendor_qcom_opensource_agm/35c3491ff5566de4f60a64ad47e74fb39cd192e0/service/src/session_obj.c \
  -o /tmp/opencode/mondrian-audio-reference/source/agm/session_obj.c
```

Expected: the PAL files contain `SessionAlsaUtils::open`, `Device::open`, and `enableDevice`; AGM contains `agm_aif_group_set_media_config` and `agm_session_aif_connect`.

- [ ] **Step 5: Verify the source identity and inventory**

Run:

```bash
rg -n 'PID_2113_ID|aw_pid_2113_dev_init|aw882xx_device_start' \
  /tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc/codecs/aw882xx
rg -n 'aw882xx_dlkm\.ko' \
  /tmp/opencode/mondrian-audio-reference/source/device-common/modules.list.vendor_dlkm
rg -n 'aw882xx_smartpa@34|aw882xx_smartpa@35|sound-channel' \
  /tmp/opencode/mondrian-audio-reference/source/devicetrees/qcom/mondrian-sm8475.dtsi
rg -n 'PAL_DEVICE_OUT_SPEAKER|TDM-LPAIF-RX-TERTIARY-VIRT-0|slot_mask' \
  /tmp/opencode/mondrian-audio-reference/source/device-mondrian/audio/resourcemanager_waipio_mtp.xml
sha256sum /tmp/opencode/mondrian-audio-reference/source/*.tar.gz \
  /tmp/opencode/mondrian-audio-reference/source/pal/* \
  /tmp/opencode/mondrian-audio-reference/source/agm/* \
  > /tmp/opencode/mondrian-audio-reference/reports/source-sha256.txt
```

Expected: PID 2113 maps to the AW driver, `aw882xx_dlkm.ko` is in the vendor-DLKM load list, both Mondrian channels are present, and the speaker resource uses the tertiary TDM backend.

### Task 3: Build the Known-Good Codec Execution Sequence

**Files:**
- Read: `/tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc/codecs/aw882xx/src/*.c`
- Read: `/tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc/codecs/aw882xx/inc/*.h`
- Read: `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/sound/soc/codecs/aw88261.c`
- Read: `/home/kreato/Sources/mondrian/mondrian/mondrian-linux/sound/soc/codecs/aw88261.h`
- Create: `/tmp/opencode/mondrian-audio-reference/reports/vendor-codec-symbols.txt`
- Create: `/tmp/opencode/mondrian-audio-reference/reports/mainline-codec-symbols.txt`

**Interfaces:**
- Consumes: exact vendor source from Task 2 and deployed r24 source.
- Produces: an ordered, source-referenced codec behavior inventory for the final comparison report.

- [ ] **Step 1: Inventory all relevant known-good functions**

Run:

```bash
rg -n 'aw882xx_i2c_probe|aw882xx_hw_reset|aw882xx_read_chipid|aw_pid_2113_dev_init|aw_pid_2113_frcset_check|aw_pid_2113_reg_force_set|aw882xx_dev_reg_update|aw_dev_reg_fw_update|aw882xx_device_start|aw_dev_i2s_enable|aw882xx_set_tx_en|aw882xx_device_stop|aw882xx_dev_init_cali_re|aw_dev_cali_re_update|aw882xx_mute' \
  /tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc/codecs/aw882xx \
  > /tmp/opencode/mondrian-audio-reference/reports/vendor-codec-symbols.txt
```

Expected: every named function resolves to an exact source file and line.

- [ ] **Step 2: Inventory the deployed r24 equivalents**

Run:

```bash
rg -n 'aw88261_i2c_probe|aw88261_dev_init|aw88261_dev_reg_update|aw88261_dev_start|aw88261_dev_i2s_tx_enable|aw88261_dev_stop|aw88261_dev_set_vcalb|aw88261_set_tdm_slot|aw88261_mute' \
  /home/kreato/Sources/mondrian/mondrian/mondrian-linux/sound/soc/codecs/aw88261.c \
  > /tmp/opencode/mondrian-audio-reference/reports/mainline-codec-symbols.txt
```

Expected: r24 probe, profile, start, TX, calibration, TDM validation, mute, and stop functions all resolve.

- [ ] **Step 3: Trace PID 2113 probe and initialization in execution order**

Read the complete bodies and immediate callers of:

```text
aw882xx_i2c_probe
aw882xx_hw_reset
aw882xx_read_chipid
aw882xx_init
aw_pid_2113_dev_init
aw_pid_2113_frcset_check
aw_pid_2113_reg_force_set
```

Record every PID 2113 register write, mask, delay, error path, and condition. Verify each numeric bit definition against `aw882xx_pid_2113_reg.h`; do not infer it from another PID header.

Expected: the sequence explicitly distinguishes one-time probe writes, FRCSET writes, and writes deferred until PA start.

- [ ] **Step 4: Trace ACF profile loading and register application**

Read the complete bodies and callers of:

```text
aw882xx_load_fw
aw882xx_dev_parse_check_acf
aw882xx_dev_parse_acf
aw882xx_device_init
aw882xx_dev_prof_update
aw882xx_dev_reg_update
aw_dev_reg_fw_update
```

Record whether profile writes are modified after ACF application, whether failed writes abort the sequence, and whether calibration can overwrite an earlier error.

Expected: every post-ACF runtime override is identified separately from ACF-owned values.

- [ ] **Step 5: Trace known-good start and stop sequencing**

Read the complete bodies and callers of:

```text
aw882xx_mute
aw882xx_start_pa
aw882xx_device_start
aw_dev_pwd
aw_dev_amppd
aw_dev_mute
aw_dev_uls_hmute
aw_dev_i2s_enable
aw882xx_set_tx_en
aw_pid_2113_reg_force_set
aw882xx_device_stop
```

Record the exact order of PLL checks, TX feedback, boost setup, AMPPD, hard mute, external DSP TX module enable, retry behavior, and shutdown.

Expected: one ordered sequence exists for start success and one for each failure rollback path.

- [ ] **Step 6: Compare codec behavior against r24 without editing it**

Required comparison rows:

```text
reset timing
PID 2113 EFCTRL/FRCSET initialization
ACF register ownership
profile-write error propagation
VCALB/calibration source
I2SCTRL2 ownership
I2SCTRL3 TX restore
I2SCFG1 handling
PLL validation
boost force/recover
AMP power and mute ordering
external DSP TX module enable
delayed-work retry/start behavior
stop and rollback behavior
```

Expected: each row is classifiable as equivalent, irrelevant, configuration-only, plausible silence cause, or requiring runtime confirmation. No row is left unresolved merely because function names differ.

### Task 4: Trace the Working TDM, PAL, AGM, and Mixer Path

**Files:**
- Read: `/tmp/opencode/mondrian-audio-reference/source/devicetrees/qcom/mondrian-sm8475.dtsi`
- Read: `/tmp/opencode/mondrian-audio-reference/source/devicetrees/qcom/audio/xiaomi-sm8450-common.dtsi`
- Read: `/tmp/opencode/mondrian-audio-reference/source/devicetrees/qcom/audio/msm-audio-lpass.dtsi`
- Read: `/tmp/opencode/mondrian-audio-reference/source/devicetrees/qcom/audio/waipio-audio-overlay.dtsi`
- Read: `/tmp/opencode/mondrian-audio-reference/source/device-mondrian/audio/resourcemanager_waipio_mtp.xml`
- Read: `/tmp/opencode/mondrian-audio-reference/source/device-mondrian/audio/mixer_paths_waipio_mtp.xml`
- Read: `/tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc/waipio.c`
- Read: `/tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc/msm_common.c`
- Read: `/tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc/msm_dailink.h`
- Read: `/tmp/opencode/mondrian-audio-reference/source/pal/*.cpp`
- Read: `/tmp/opencode/mondrian-audio-reference/source/agm/*.c`

**Interfaces:**
- Consumes: the known-good source snapshot and exact Mondrian PAL XML.
- Produces: a layer-by-layer transport table that separates frontend PCM format, PAL group media config, machine-driver clocking, DSP endpoint payload, physical lane, and amplifier slot selection.

- [ ] **Step 1: Verify the physical channel and GPIO map**

Run:

```bash
rg -n 'aw882xx_smartpa@34|aw882xx_smartpa@35|sound-channel|reset-gpio|irq-gpio|spksw-gpio|gpio121|gpio122|gpio123|gpio124' \
  /tmp/opencode/mondrian-audio-reference/source/devicetrees/qcom/mondrian-sm8475.dtsi
```

Expected:

```text
0x34 = channel 0, reset GPIO1, IRQ GPIO88, GPIO52 receiver switch
0x35 = channel 1, reset GPIO3, IRQ GPIO63, no receiver switch
GPIO121 = tertiary clock
GPIO123 = tertiary frame sync
GPIO122 and GPIO124 = tertiary data pins
```

- [ ] **Step 2: Trace the PAL speaker resource and mixer activation**

Run:

```bash
rg -n 'PAL_DEVICE_OUT_SPEAKER|TDM-LPAIF-RX-TERTIARY-VIRT-0|speaker-mono-2|speaker-mono|slot_mask|group_device|aw_dev_0_switch|aw_dev_1_switch|aw_dev_0_prof|aw_dev_1_prof' \
  /tmp/opencode/mondrian-audio-reference/source/device-mondrian/audio/resourcemanager_waipio_mtp.xml \
  /tmp/opencode/mondrian-audio-reference/source/device-mondrian/audio/mixer_paths_waipio_mtp.xml
```

Expected: normal `speaker` playback enables both channels with Music profiles, while `speaker-mono` disables channel 1 and `handset` changes only GPIO52/top.

- [ ] **Step 3: Separate the four format layers**

Record these known-good values with their exact XML/DTS/source reference:

```text
PAL logical speaker endpoint: 48 kHz, 2 channels, 24-bit
PAL grouped physical TDM config: 3 channels, S32_LE, slot mask 0x7
AW channel map: channel 0 top, channel 1 bottom
TDM backend: TDM-LPAIF-RX-TERTIARY-VIRT-0
VI feedback backend: TDM-LPAIF-TX-TERTIARY
```

Then trace `SessionAlsaUtils::open`, `Device::open`, `enableDevice`, `agm_aif_set_media_config`, `agm_aif_group_set_media_config`, and `agm_session_aif_connect` to determine which values reach endpoint media config versus group media config.

Expected: the report states whether `slot_mask=0x7` changes the DSP TDM lane/slot payload, only allocates grouped channels, or performs both actions.

- [ ] **Step 4: Trace downstream machine-driver clock and slot behavior**

Run:

```bash
rg -n 'tdm-max-slots|tdm-audio-intf|tert-mi2s|TDM-LPAIF-RX-TERTIARY|msm_common_snd_hw_params|msm_common_snd_init|snd_soc_dai_set_tdm_slot|set_tdm_slot' \
  /tmp/opencode/mondrian-audio-reference/source/devicetrees/qcom \
  /tmp/opencode/mondrian-audio-reference/source/kernel-modules/qcom/opensource/audio-kernel/asoc
```

Expected: the exact source explains whether the reported 1.536 MHz value is a bit clock, a base/internal clock, or another clock attribute; no frequency is labeled by inference alone. The absence or presence of a codec `set_tdm_slot` call is explicitly proven.

- [ ] **Step 5: Compare the working transport against mainline r24**

Read and compare:

```text
device/testing/firmware-xiaomi-mondrian/module_tdm.m4
device/testing/firmware-xiaomi-mondrian/subgraph-device-tdm-playback.m4
device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4
mondrian-linux/sound/soc/qcom/qdsp6/audioreach.c
mondrian-linux/sound/soc/qcom/qdsp6/topology.c
```

Required comparison rows:

```text
frontend sample format and channel count
physical/group channel count
slot count and slot width
active audio slot mask
active physical lane mask
frame-sync rate, source, mode, polarity, and data delay
bit-clock ID and effective frequency
control-data-out enable
backend interface and index
codec channel-to-slot selection
VI feedback enable and transport
```

Expected: the `0x7` versus `0x3` difference is classified only after tracing PAL group media configuration into AGM/DSP behavior. It is not assumed to be either causal or irrelevant.

### Task 5: Verify the Shipped Module, Kernel Config, and DTBO

**Files:**
- Create: `/tmp/opencode/mondrian-audio-reference/unpacked/*`
- Create: `/tmp/opencode/mondrian-audio-reference/ramdisks/*`
- Create: `/tmp/opencode/mondrian-audio-reference/dtbo/entries/*.dtbo`
- Create: `/tmp/opencode/mondrian-audio-reference/dtbo/dts/*.dts`
- Create: `/tmp/opencode/mondrian-audio-reference/reports/module-*.txt`
- Create: `/tmp/opencode/mondrian-audio-reference/reports/kernel.config`

**Interfaces:**
- Consumes: verified image copies from Task 1 and source behavior from Tasks 3-4.
- Produces: evidence that the known-good images contain the expected source-derived module/configuration, plus disassembly only where source and binary do not agree.

- [ ] **Step 1: Unpack boot and vendor boot with the installed Android tool**

Run:

```bash
/etc/profiles/per-user/kreato/bin/unpack_bootimg \
  --boot_img /tmp/opencode/mondrian-audio-reference/input/boot.img \
  --out /tmp/opencode/mondrian-audio-reference/unpacked/boot \
  --format info \
  > /tmp/opencode/mondrian-audio-reference/reports/boot-info.txt
/etc/profiles/per-user/kreato/bin/unpack_bootimg \
  --boot_img /tmp/opencode/mondrian-audio-reference/input/vendor_boot.img \
  --out /tmp/opencode/mondrian-audio-reference/unpacked/vendor_boot \
  --format info \
  > /tmp/opencode/mondrian-audio-reference/reports/vendor-boot-info.txt
```

Expected: boot header v4; vendor boot header v4; one boot ramdisk and two named vendor ramdisk fragments.

- [ ] **Step 2: Validate and decompress the three legacy-LZ4 ramdisks**

Run:

```bash
/nix/store/z9hvq1zxh8lcrx93pszw5i0ll3nhq8xq-lz4-1.10.0/bin/lz4 -t \
  /tmp/opencode/mondrian-audio-reference/unpacked/boot/ramdisk
/nix/store/z9hvq1zxh8lcrx93pszw5i0ll3nhq8xq-lz4-1.10.0/bin/lz4 -t \
  /tmp/opencode/mondrian-audio-reference/unpacked/vendor_boot/vendor_ramdisk00
/nix/store/z9hvq1zxh8lcrx93pszw5i0ll3nhq8xq-lz4-1.10.0/bin/lz4 -t \
  /tmp/opencode/mondrian-audio-reference/unpacked/vendor_boot/vendor_ramdisk01
/nix/store/z9hvq1zxh8lcrx93pszw5i0ll3nhq8xq-lz4-1.10.0/bin/lz4 -d \
  /tmp/opencode/mondrian-audio-reference/unpacked/boot/ramdisk \
  /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/boot.cpio
/nix/store/z9hvq1zxh8lcrx93pszw5i0ll3nhq8xq-lz4-1.10.0/bin/lz4 -d \
  /tmp/opencode/mondrian-audio-reference/unpacked/vendor_boot/vendor_ramdisk00 \
  /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/vendor-platform.cpio
/nix/store/z9hvq1zxh8lcrx93pszw5i0ll3nhq8xq-lz4-1.10.0/bin/lz4 -d \
  /tmp/opencode/mondrian-audio-reference/unpacked/vendor_boot/vendor_ramdisk01 \
  /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/vendor-dlkm.cpio
```

Expected: all LZ4 integrity checks pass and all outputs are CPIO archives.

- [ ] **Step 3: Inspect CPIO names before extracting**

Run:

```bash
cpio --list --verbose --quiet \
  < /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/boot.cpio \
  > /tmp/opencode/mondrian-audio-reference/reports/boot-cpio.txt
cpio --list --verbose --quiet \
  < /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/vendor-platform.cpio \
  > /tmp/opencode/mondrian-audio-reference/reports/vendor-platform-cpio.txt
cpio --list --verbose --quiet \
  < /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/vendor-dlkm.cpio \
  > /tmp/opencode/mondrian-audio-reference/reports/vendor-dlkm-cpio.txt
rg -n 'aw882xx_dlkm\.ko|modules\.load|modules\.dep' \
  /tmp/opencode/mondrian-audio-reference/reports/vendor-dlkm-cpio.txt
```

Expected: the DLKM fragment lists `aw882xx_dlkm.ko`; no listing contains an absolute path or `..` traversal component.

- [ ] **Step 4: Extract unprivileged into the checked empty directories**

Run:

```bash
cpio --extract --make-directories --preserve-modification-time \
  --unconditional --no-absolute-filenames --no-preserve-owner \
  --directory=/tmp/opencode/mondrian-audio-reference/ramdisks/root/boot \
  < /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/boot.cpio
cpio --extract --make-directories --preserve-modification-time \
  --unconditional --no-absolute-filenames --no-preserve-owner \
  --directory=/tmp/opencode/mondrian-audio-reference/ramdisks/root/vendor-platform \
  < /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/vendor-platform.cpio
cpio --extract --make-directories --preserve-modification-time \
  --unconditional --no-absolute-filenames --no-preserve-owner \
  --directory=/tmp/opencode/mondrian-audio-reference/ramdisks/root/vendor-dlkm \
  < /tmp/opencode/mondrian-audio-reference/ramdisks/cpio/vendor-dlkm.cpio
```

Expected: extraction uses no `sudo`, preserves the private root, and writes nothing outside the analysis workspace.

- [ ] **Step 5: Identify and inspect the shipped AW module**

Run:

```bash
rg --files /tmp/opencode/mondrian-audio-reference/ramdisks/root/vendor-dlkm \
  | rg '/aw882xx_dlkm\.ko$' \
  > /tmp/opencode/mondrian-audio-reference/reports/aw-module-path.txt
module=$(</tmp/opencode/mondrian-audio-reference/reports/aw-module-path.txt)
modinfo "$module" \
  > /tmp/opencode/mondrian-audio-reference/reports/aw-module-info.txt
/nix/store/sa0593q2whb4mgwjvxwczpj526y6l5x-aarch64-unknown-linux-gnu-binutils-2.46/bin/aarch64-unknown-linux-gnu-readelf \
  --wide --headers --sections --symbols \
  "$module" \
  > /tmp/opencode/mondrian-audio-reference/reports/aw-module-readelf.txt
/nix/store/sa0593q2whb4mgwjvxwczpj526y6l5x-aarch64-unknown-linux-gnu-binutils-2.46/bin/aarch64-unknown-linux-gnu-nm \
  --numeric-sort \
  "$module" \
  > /tmp/opencode/mondrian-audio-reference/reports/aw-module-nm.txt
sha256sum "$module" \
  > /tmp/opencode/mondrian-audio-reference/reports/aw-module-sha256.txt
```

Expected: module name `aw882xx_dlkm`, ARM64 ELF format, and symbols or strings corresponding to the Task 3 function map.

- [ ] **Step 6: Extract and verify the shipped kernel configuration**

Run:

```bash
PATH=/nix/store/z9hvq1zxh8lcrx93pszw5i0ll3nhq8xq-lz4-1.10.0/bin:$PATH \
  /home/kreato/Sources/mondrian/mondrian/mondrian-linux/scripts/extract-ikconfig \
  /tmp/opencode/mondrian-audio-reference/unpacked/boot/kernel \
  > /tmp/opencode/mondrian-audio-reference/reports/kernel.config
rg -n 'CONFIG_SND_SOC|CONFIG_MODULES|CONFIG_IKCONFIG' \
  /tmp/opencode/mondrian-audio-reference/reports/kernel.config
```

Expected: kernel release `5.10.256-gki-ge682ed2de56f`; modules and IKCONFIG enabled; AW882xx remains an external vendor module rather than a GKI built-in.

- [ ] **Step 7: Disassemble only binary behavior that source does not explain**

If Task 3 finds an exported/local function, constant, or sequencing branch present in the shipped module but absent from pinned source, run:

```bash
module=$(</tmp/opencode/mondrian-audio-reference/reports/aw-module-path.txt)
/nix/store/sa0593q2whb4mgwjvxwczpj526y6l5x-aarch64-unknown-linux-gnu-binutils-2.46/bin/aarch64-unknown-linux-gnu-objdump \
  -dr \
  "$module" \
  > /tmp/opencode/mondrian-audio-reference/reports/aw-module-disassembly.txt
```

Expected: disassembly is used only to resolve a named source/binary mismatch; it is not treated as a substitute for available source.

- [ ] **Step 8: Extract the 92 Android DTBO entries with bounded validation**

Create `/tmp/opencode/mondrian-audio-reference/extract_dtbo.py` with this exact content using `apply_patch`:

```python
import struct
import sys
from pathlib import Path

image = Path(sys.argv[1]).read_bytes()
output = Path(sys.argv[2])

magic, total_size, header_size, entry_size, count, table_offset, page_size, version = struct.unpack_from(
    ">8I", image, 0
)
if magic != 0xD7B7AB1E:
    raise SystemExit("invalid Android DT table magic")
if header_size < 32 or entry_size < 32:
    raise SystemExit("unsupported DT table layout")
if total_size > len(image):
    raise SystemExit("DT table exceeds input image")
if table_offset + count * entry_size > total_size:
    raise SystemExit("DT entry table exceeds declared payload")

for index in range(count):
    offset = table_offset + index * entry_size
    dt_size, dt_offset = struct.unpack_from(">2I", image, offset)
    if dt_offset + dt_size > total_size:
        raise SystemExit(f"entry {index} exceeds declared payload")
    blob = image[dt_offset : dt_offset + dt_size]
    fdt_magic, fdt_size = struct.unpack_from(">2I", blob, 0)
    if fdt_magic != 0xD00DFEED or fdt_size != dt_size:
        raise SystemExit(f"entry {index} has invalid FDT framing")
    (output / f"{index:03d}.dtbo").write_bytes(blob)

print(count)
```

Run:

```bash
python3 /tmp/opencode/mondrian-audio-reference/extract_dtbo.py \
  /tmp/opencode/mondrian-audio-reference/input/dtbo.img \
  /tmp/opencode/mondrian-audio-reference/dtbo/entries \
  > /tmp/opencode/mondrian-audio-reference/reports/dtbo-count.txt
```

Expected: output count is exactly `92`; every output begins with FDT magic and stays within the declared DT table size.

- [ ] **Step 9: Decompile and identify the Mondrian audio overlays**

Run:

```bash
for blob in /tmp/opencode/mondrian-audio-reference/dtbo/entries/*.dtbo; do
  name=${blob##*/}
  /nix/store/vr00x34nq68a86c62svc9mjjw3hqvs32-dtc-1.7.2/bin/dtc \
    -I dtb -O dts -s \
    -o "/tmp/opencode/mondrian-audio-reference/dtbo/dts/${name%.dtbo}.dts" \
    "$blob" \
    2>> /tmp/opencode/mondrian-audio-reference/reports/dtc-warnings.txt
rg -l 'aw882xx_smartpa|sound-channel|mondrian' \
  /tmp/opencode/mondrian-audio-reference/dtbo/dts \
  > /tmp/opencode/mondrian-audio-reference/reports/mondrian-dtbo-files.txt
```

Expected: the matching overlays reproduce the source-level `0x34`/`0x35`, channel, reset, IRQ, GPIO52, and tertiary-TDM properties from Task 4.

### Task 6: Produce and Verify the Evidence Report

**Files:**
- Create: `docs/superpowers/reports/2026-08-11-mondrian-working-audio-comparison.md`
- Read: all reports under `/tmp/opencode/mondrian-audio-reference/reports/`
- Read: `docs/superpowers/specs/2026-08-11-mondrian-working-audio-reverse-engineering-design.md`

**Interfaces:**
- Consumes: source analysis, binary verification, DTBO verification, and mainline r24 comparison.
- Produces: one reviewable decision document and no production behavior change.

- [ ] **Step 1: Create the report with mandatory evidence sections**

Verify `docs/superpowers` is the intended parent, then create the report directory:

```bash
test -d docs/superpowers
install -d docs/superpowers/reports
```

Use `apply_patch` to create the report with these exact headings:

```markdown
# Mondrian Working Audio Comparison

## Artifact Provenance
## Known-Good Codec Sequence
## Mainline r24 Codec Sequence
## Codec Difference Table
## Known-Good Transport Layers
## Mainline r24 Transport Layers
## Transport Difference Table
## Binary Verification
## DTBO Verification
## Findings
## Decision
## Residual Risks
```

Expected: every factual statement includes an exact repository revision and path/line reference, local extracted artifact hash/path, or current mainline path/line reference.

- [ ] **Step 2: Populate the codec difference table**

Use these exact columns:

```markdown
| Stage/order | Known-good evidence | Known-good action | Mainline r24 action | Classification | Expected effect |
|---|---|---|---|---|---|
```

Include every mandatory row from Task 3 Step 6. Numeric masks must be shown both as register names and hexadecimal values.

Expected: ACF-owned values and runtime overrides are never combined in one row; start failure and rollback behavior is represented separately from successful start.

- [ ] **Step 3: Populate the transport layer and difference tables**

Use these exact columns:

```markdown
| Layer | Known-good format/config | Consumer/API | Mainline r24 equivalent | Proven relationship |
|---|---|---|---|---|
```

```markdown
| Parameter | Known-good evidence | Mainline r24 evidence | Classification | Required next evidence |
|---|---|---|---|---|
```

The report must independently account for logical PCM, PAL endpoint media config, PAL group media config, AGM metadata, DSP TDM interface config, DSP lane config, AP pinctrl, and codec slot selection.

Expected: the report explicitly adjudicates `3 channels/S32/slot_mask=0x7` versus `4x32/slot_mask=0x3`, including whether they are values for the same API.

- [ ] **Step 4: Apply the decision gate**

Allowed decision outcomes:

```text
Concrete software mismatch found
Software-visible paths equivalent
Missing binary artifact prevents conclusion
```

For `Concrete software mismatch found`, include exactly one recommended next change, its source reference, the expected register/DSP readback, and the focused regression that must fail before implementation.

For `Software-visible paths equivalent`, identify the remaining physical boundary as DATA1 delivery, amplifier hardware, or bottom speaker/load without proposing another speculative register write.

For `Missing binary artifact prevents conclusion`, name the exact missing partition/module/file and why neither source nor supplied images can replace it.

Expected: no code, package, topology, phone, or test-tone change is performed in this plan.

- [ ] **Step 5: Verify report completeness and absence of placeholders**

Run:

```bash
rg -n '^## (Artifact Provenance|Known-Good Codec Sequence|Mainline r24 Codec Sequence|Codec Difference Table|Known-Good Transport Layers|Mainline r24 Transport Layers|Transport Difference Table|Binary Verification|DTBO Verification|Findings|Decision|Residual Risks)$' \
  docs/superpowers/reports/2026-08-11-mondrian-working-audio-comparison.md
if rg -n 'TBD|TODO|FIXME|placeholder|unknown value|fill in' \
  docs/superpowers/reports/2026-08-11-mondrian-working-audio-comparison.md; then
  exit 1
fi
rg -n '0x7|0x3|PID_2113|aw882xx_dlkm\.ko|0x34|0x35|DATA1|Classification|Decision' \
  docs/superpowers/reports/2026-08-11-mondrian-working-audio-comparison.md
```

Expected: all 12 headings appear once, no placeholder pattern is found, and all mandatory identity/transport evidence appears.

- [ ] **Step 6: Request focused review before any implementation**

Review questions:

```text
Does every plausible-silence classification cite a known-good source or shipped binary?
Are PAL group config and DSP TDM interface config kept separate unless code proves a conversion?
Does the recommendation make the smallest evidence-backed change?
Is the expected runtime readback stated before deployment?
Were all supplied images kept read-only and unflashed?
```

Expected: review completes before creating any regression, source patch, package revision, flash image, or audible test request.

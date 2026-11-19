# Mondrian Legacy TDM Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove stereo speaker playback on Xiaomi Mondrian with the stock ADSP's legacy AudioReach TDM sink ABI.

**Architecture:** Keep the existing GPR/APM stream and mixer graphs, but replace the unsupported QAIF Audio IF endpoint with `MODULE_ID_TDM_SINK`. Execute three separately deployable checkpoints: truthful graph-open error handling, minimal legacy sink graph-open acceptance, and complete stock-compatible tertiary TDM configuration with endpoint-owned clocking.

**Tech Stack:** Linux ASoC, Qualcomm AudioReach/GPR/APM, AudioReach topology M4, Alpine APKBUILD, pmbootstrap, fastboot, ALSA, AW88261.

## Global Constraints

- Do not use git commands, worktrees, staging, or commits.
- Use `/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap` when pmbootstrap is required.
- User runs host sudo-required build commands; phone SSH user is literally `user`, then use `sudo`.
- Flash only active-slot `boot_b`; do not flash `userdata` or `vendor_boot`.
- Preserve Android boot header v4 and the existing boot layout by installing APKs and using boot-deploy.
- Keep scope to `MultiMedia1` stereo playback through `TERTIARY_TDM_RX_0` and the two AW88261 amplifiers.
- Use stock-compatible framing: 48 kHz, S16_LE stereo, four 32-bit slots, active slots 0 and 1, DSP_A, normal frame polarity, and one-BCLK data delay.
- Use legacy tertiary TDM clock ID `0x204` at 6.144 MHz with attribute `4` and root `0`; do not request Audio IF2 clock `0x504`.
- Stop at the first rejected DSP command at every device checkpoint.

---

### Task 1: Make Graph-Open Failure Authoritative

**Files:**
- Create: `device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh`
- Modify: `../mondrian-linux/sound/soc/qcom/qdsp6/q6apm.h:52-70`
- Modify: `../mondrian-linux/sound/soc/qcom/qdsp6/q6apm.c:41-93`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD:6,87`
- Replace: `device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz`

**Interfaces:**
- Consumes: `q6apm_send_cmd_sync(struct q6apm *, const struct gpr_pkt *, uint32_t)` and `graph_idr` ownership in `struct q6apm`.
- Produces: a dedicated graph-lifecycle mutex serializes graph get/open/put; `q6apm_get_audioreach_graph()` returns `ERR_PTR(ret)` when `APM_CMD_GRAPH_OPEN` fails and leaves no graph in `graph_idr`.

- [ ] **Step 1: Add a failing source-contract test**

Create `device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh`:

```sh
#!/bin/sh
set -eu

root="$(CDPATH='' cd -- "$(dirname "$0")/../../.." && pwd)"
kernel="$root/../mondrian-linux"
q6apm="$kernel/sound/soc/qcom/qdsp6/q6apm.c"

test -f "$q6apm"

rg -q 'ret = q6apm_send_cmd_sync\(apm, graph->graph, 0\);' "$q6apm"
rg -q -U 'if \(ret\) \{\n\s*mutex_lock\(&apm->lock\);\n\s*idr_remove\(&apm->graph_idr, graph_id\);\n\s*mutex_unlock\(&apm->lock\);' "$q6apm"
rg -q -U 'kfree\(graph->graph\);\n\s*kfree\(graph\);\n\s*return ERR_PTR\(ret\);' "$q6apm"
grep -Fq 'struct mutex graph_lock;' "$kernel/sound/soc/qcom/qdsp6/q6apm.h"
grep -Fq 'mutex_init(&apm->graph_lock);' "$q6apm"
rg -q -U '(?s)q6apm_get_audioreach_graph.*mutex_lock\(&apm->graph_lock\);' "$q6apm"
rg -q -U '(?s)q6apm_put_audioreach_graph.*mutex_lock\(&apm->graph_lock\);' "$q6apm"
```

Make it executable:

```bash
chmod +x device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh
```

- [ ] **Step 2: Run the test and verify RED**

```bash
device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh
```

Expected: non-zero exit because `q6apm_get_audioreach_graph()` currently ignores the return from `q6apm_send_cmd_sync()`.

- [ ] **Step 3: Serialize the graph lifecycle**

Add `struct mutex graph_lock;` to `struct q6apm` and initialize it in
`apm_probe()`. Hold this mutex across the complete
`q6apm_get_audioreach_graph()` lookup/create/open path, including reference
acquisition and every return. Hold the same mutex across
`q6apm_put_audioreach_graph()` graph-close, IDR removal, and free path.

The existing `apm->lock` remains the command/IDR lock. Do not hold
`apm->lock` across a synchronous DSP command; `q6apm_send_cmd_sync()` acquires
that lock internally.

- [ ] **Step 4: Propagate graph-open failure and clean local state**

In `q6apm_get_audioreach_graph()`, change the local declarations to:

```c
	int id, ret;
```

Replace the ignored graph-open call with:

```c
	ret = q6apm_send_cmd_sync(apm, graph->graph, 0);
	if (ret) {
		mutex_lock(&apm->lock);
		idr_remove(&apm->graph_idr, graph_id);
		mutex_unlock(&apm->lock);
		kfree(graph->graph);
		kfree(graph);
		return ERR_PTR(ret);
	}
```

Do not call `q6apm_put_audioreach_graph()` in this path because it sends `APM_CMD_GRAPH_CLOSE` for a graph that did not open.

- [ ] **Step 5: Run the focused test and verify GREEN**

```bash
device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh
```

Expected: exit 0 with no output.

- [ ] **Step 6: Regenerate the packaged kernel source and bump to r18**

```bash
tar --exclude-vcs --exclude='*.o' --exclude='*.cmd' --exclude='*.ko' \
  --exclude='*.dtb' --exclude='*.dtbo' --exclude='.config' \
  --exclude='Module.symvers' --exclude='System.map' --exclude='vmlinux' \
  -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux -czf \
  /home/kreato/Sources/mondrian/mondrian/pmaports/device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz .
sha512sum device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz
```

Set `pkgrel=18` in the kernel APKBUILD and replace only the checksum before `linux-local.tar.gz` with the printed digest.

- [ ] **Step 7: Verify package metadata and archive contents**

```bash
sh -n device/testing/linux-postmarketos-qcom-sm8450/APKBUILD
grep -Fqx 'pkgrel=18' device/testing/linux-postmarketos-qcom-sm8450/APKBUILD
test "$(sha512sum device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz | cut -d' ' -f1)" = "$(awk '/linux-local\.tar\.gz$/ { print $1 }' device/testing/linux-postmarketos-qcom-sm8450/APKBUILD)"
tar -xOf device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz ./sound/soc/qcom/qdsp6/q6apm.c | rg -U '(?s)ret = q6apm_send_cmd_sync.*return ERR_PTR\(ret\);'
```

Expected: all commands exit 0.

- [ ] **Step 8: Build, install, and flash the r18 checkpoint**

Have the user run:

```bash
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build linux-postmarketos-qcom-sm8450 --force
```

Then deploy the exact r18 APK:

```bash
scp /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r18.apk user@172.16.42.1:/tmp/
ssh user@172.16.42.1 'sudo apk add --allow-untrusted --force-overwrite /tmp/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r18.apk'
scp user@172.16.42.1:/boot/boot.img /tmp/mondrian-legacy-graph-open-r18-boot.img
ssh user@172.16.42.1 'sudo reboot bootloader'
timeout 90 bash -c 'until fastboot devices | rg -q "[[:space:]]fastboot$"; do sleep 1; done'
fastboot getvar current-slot
fastboot flash boot_b /tmp/mondrian-legacy-graph-open-r18-boot.img
fastboot reboot
```

Expected: `current-slot: b`; only `boot_b` is written.

- [ ] **Step 9: Verify graph-open rejection now stops subsequent commands**

After reboot:

```bash
ssh user@172.16.42.1 'sudo dmesg -C; amixer -c 0 sset "TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1" on >/dev/null; timeout 3 aplay -D hw:0,0 --period-size=480 --buffer-size=1920 -f S16_LE -r 48000 -c 2 /dev/zero >/tmp/aplay-graph-open.log 2>&1; cat /tmp/aplay-graph-open.log; sudo dmesg | grep -E "DSP returned error|Failed to open graph|Failed to set media format|GRAPH_CLOSE|ASoC error"'
```

Expected: the existing Audio IF graph still fails open, but no media-format, prepare, or graph-close command follows that graph-open failure. Retain the exact first DSP error.

### Task 2: Prove The Stock ADSP Accepts A Minimal Legacy TDM Sink

**Files:**
- Modify: `../mondrian-linux/sound/soc/qcom/qdsp6/audioreach.h:12-39`
- Modify: `../mondrian-linux/sound/soc/qcom/qdsp6/topology.c:894-917`
- Modify: `../mondrian-linux/sound/soc/codecs/aw88261.c`
- Modify: `../mondrian-linux/sound/soc/codecs/aw88261.h`
- Modify: `../mondrian-linux/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts:1006-1042`
- Create: `device/testing/firmware-xiaomi-mondrian/module_tdm.m4`
- Modify: `device/testing/firmware-xiaomi-mondrian/subgraph-device-tdm-playback.m4:8-53`
- Modify: `device/testing/firmware-xiaomi-mondrian/APKBUILD:3,19-28,94-104`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD:6,87`
- Replace: `device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz`

**Interfaces:**
- Consumes: existing serial-interface topology tokens `262` through `276` and `audioreach_widget_audio_if_module_load()` field parsing.
- Produces: a topology graph containing `MODULE_ID_TDM_SINK = 0x0700100E`; the media-format dispatcher intentionally performs no TDM configuration at this checkpoint; AW88261 accepts and programs four-slot/6.144 MHz framing while retaining eight-slot/12.288 MHz support.

- [ ] **Step 1: Extend the focused test for the minimal legacy graph**

Append to `test-legacy-tdm-proof.sh`:

```sh
ar_h="$kernel/sound/soc/qcom/qdsp6/audioreach.h"
topology_c="$kernel/sound/soc/qcom/qdsp6/topology.c"
dts="$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
firmware="$root/device/testing/firmware-xiaomi-mondrian"

grep -Fq '#define MODULE_ID_TDM_SINK' "$ar_h"
grep -Fq '#define MODULE_ID_TDM_SOURCE' "$ar_h"
rg -q -U 'case MODULE_ID_TDM_SINK:\n\s*case MODULE_ID_TDM_SOURCE:\n\s*ret = audioreach_widget_audio_if_module_load' "$topology_c"
grep -Fq 'MODULE_ID_TDM_SINK' "$firmware/module_tdm.m4"
grep -Fq 'AR_MODULE_TDM_RX' "$firmware/subgraph-device-tdm-playback.m4"
! grep -Fq 'AR_MODULE_AUDIO_IF_RX' "$firmware/subgraph-device-tdm-playback.m4"
! grep -Fq 'LPASS_CLK_ID_INTF2_IBIT' "$dts"
test "$(grep -Fc 'dai-tdm-slot-num = <4>;' "$dts")" -eq 2
aw_c="$kernel/sound/soc/codecs/aw88261.c"
aw_h="$kernel/sound/soc/codecs/aw88261.h"
grep -Fq 'AW88261_SLOT_NUM_TDM4S_VALUE' "$aw_h"
grep -Fq 'AW88261_SLOT_NUM_TDM8S_VALUE' "$aw_h"
grep -Fq 'aw88261_dev_configure_tdm' "$aw_c"
grep -Fq 'case 4:' "$aw_c"
grep -Fq 'case 8:' "$aw_c"
grep -Fq 'aw88261->tdm_sysclk = AW88261_TDM_RATE * slots * slot_width;' "$aw_c"
grep -Fq 'freq != aw88261->tdm_sysclk' "$aw_c"
```

- [ ] **Step 2: Run the test and verify RED**

```bash
device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh
```

Expected: non-zero exit because the legacy module definitions and topology do not exist.

- [ ] **Step 3: Define the legacy TDM module IDs**

Add beside the I2S module IDs in `audioreach.h`:

```c
#define MODULE_ID_TDM_SINK		0x0700100E
#define MODULE_ID_TDM_SOURCE		0x0700100F
```

- [ ] **Step 4: Allow topology loading for legacy TDM widgets**

Add these cases immediately after the Audio IF cases in `audioreach_widget_load_buffer()`:

```c
	case MODULE_ID_TDM_SINK:
	case MODULE_ID_TDM_SOURCE:
		ret = audioreach_widget_audio_if_module_load(mod, mod_array);
		if (ret)
			return ret;
		break;
```

Do not add TDM cases to `audioreach_set_media_format()` yet. Its default `rc = 0` is intentional for the graph-open-only checkpoint.

- [ ] **Step 5: Create the legacy topology module macro**

Create `device/testing/firmware-xiaomi-mondrian/module_tdm.m4`:

```m4
# Copyright, Linaro Ltd, 2023
# SPDX-License-Identifier: BSD-3-Clause
include(`util/util.m4') dnl

define(`MODULE_ID_TDM_SINK', `0x0700100E') dnl
define(`MODULE_ID_TDM_SOURCE', `0x0700100F') dnl

dnl AR_MODULE_TDM_RX(index, sgidx, container-idx, iid, maxip-ports,
dnl max-op-ports, src-port, dst-port, lpaif-type, intf-idx, fmt,
dnl sd-line-idx, dev-name, dst-iid, slot-mask, nslots, slot-width,
dnl intf-mode, lane-mask, frame-sync-rate, sync-src, sync-mode,
dnl invert-sync, data-delay, bit-clk-type, inv-int-clk, inv-ext-clk)
define(`AR_MODULE_TDM_RX',
`'
`SectionVendorTuples."NAME_PREFIX.tdm_rx$1_tuples" {'
`        tokens "audioreach_audio_if_tokens"'
`'
`        tuples."word.u32_data" {'
`                AR_TKN_U32_MODULE_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_ID STR(MODULE_ID_TDM_SINK)'
`                AR_TKN_U32_MODULE_MAX_IP_PORTS STR($5)'
`                AR_TKN_U32_MODULE_MAX_OP_PORTS STR($6)'
`                AR_TKN_U32_MODULE_SRC_OP_PORT_ID STR($7)'
`                AR_TKN_U32_MODULE_DST_IN_PORT_ID STR($8)'
`                AR_TKN_U32_MODULE_SRC_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_DST_INSTANCE_ID STR($14)'
`                AR_TKN_U32_MODULE_HW_IF_TYPE STR($9)'
`                AR_TKN_U32_MODULE_HW_IF_IDX STR($10)'
`                AR_TKN_U32_MODULE_FMT_DATA STR($11)'
`                AR_TKN_U32_MODULE_SD_LINE_IDX STR($12)'
`                AR_TKN_U32_MODULE_SLOT_MASK STR($15)'
`                AR_TKN_U16_MODULE_NSLOTS_PER_FRAME STR($16)'
`                AR_TKN_U16_MODULE_SLOT_WIDTH STR($17)'
`                AR_TKN_U32_MODULE_ACTIVE_LANE_MASK STR($19)'
`                AR_TKN_U16_MODULE_SYNC_SRC STR($21)'
`                AR_TKN_U16_MODULE_SYNC_MODE STR($22)'
`                AR_TKN_U16_MODULE_CTRL_INVERT_SYNC_PULSE STR($23)'
`                AR_TKN_U16_MODULE_CTRL_SYNC_DATA_DELAY STR($24)'
`                AR_TKN_U8_MODULE_INV_INT_BIT_CLK STR($26)'
`        }'
`}'
`'
`SectionData."NAME_PREFIX.tdm_rx$1_data" {'
`        tuples "NAME_PREFIX.tdm_rx$1_tuples"'
`}'
`'
`SectionWidget."NAME_PREFIX.tdm_rx$1" {'
`        index STR($1)'
`        type "aif_in"'
`        no_pm "true"'
`        stream_name "$13 MI2S Playback"'
`        subseq "10"'
`        data ['
`                "NAME_PREFIX.sub_graph$2_data"'
`                "NAME_PREFIX.container$3_data"'
`                "NAME_PREFIX.tdm_rx$1_data"'
`        ]'
`}') dnl
```

- [ ] **Step 6: Switch the Mondrian topology to the legacy sink**

In `subgraph-device-tdm-playback.m4`:

- Replace `include(`module_audio_if.m4')` with `include(`module_tdm.m4')`.
- Rename `AUDIO_IF_MODULE_IID` to `TDM_MODULE_IID` throughout.
- Replace `AR_MODULE_AUDIO_IF_RX` with `AR_MODULE_TDM_RX`.
- Use this exact invocation:

```m4
AR_MODULE_TDM_RX(MOD_INDEX, SG_INDEX, CONTAINER_INDEX, TDM_MODULE_IID, 1, 0, 1, 0, DEVICE_INTF_TYPE, DEVICE_INTF_INDEX, DEVICE_DATA_FORMAT, DEVICE_SD_LINE_IDX, `DEVICE_NAME', NONE_IID, 0x3, 4, 32, 0, 0x1, 48000, 1, 0, 0, 1, 0, 1, 0)
```

Update the route widget from `aif_rx$1` to `tdm_rx$1`; retain the backend TDM
DAI's historical external stream name `MI2S Playback`.

- [ ] **Step 7: Remove the rejected QAIF clock and select four slots**

Delete the entire Mondrian `&q6apmbedai` override containing `dai@38`. In both the CPU and codec nodes of `speaker-playback-dai-link`, set:

```dts
	dai-tdm-slot-num = <4>;
	dai-tdm-slot-width = <32>;
	dai-tdm-slot-rx-mask = <1 1>;
```

- [ ] **Step 8: Port AW88261 TDM register programming**

Adapt the upstream AW88261 TDM support to the local driver without replacing
its ACF/profile implementation:

- Add the slot-count and valid-slot-mask register definitions needed for the
  required four- and eight-slot modes to `aw88261.h`.
- Add `slot_num_value`, `tdm_bck_value`, `tdm_sysclk`, `tx_slotvld_mask`,
  `rxl_slotvld_mask`, and `rxr_slotvld_mask` to `struct aw88261`.
- Initialize I2S defaults in `aw88261_i2c_probe()`.
- Add `aw88261_dev_configure_tdm()` that updates `AW88261_I2SCTRL2_REG` slot
  count and valid-slot fields plus `AW88261_I2SCTRL1_REG` BCLK mode.
- Call it in `aw88261_dev_start()` after power-up and before PLL status checks,
  so it overrides profile values before the interface is validated.
- Replace the local validation-only `aw88261_dai_set_tdm_slot()` with the
  upstream slot/mask/slot-width state programming, including 4- and 8-slot
  cases. Reject masks outside the 16 representable hardware slots.
- Set `aw88261->tdm_sysclk = AW88261_TDM_RATE * slots * slot_width` for nonzero
  TDM slot configuration; clear it for I2S mode.
- Change `aw88261_dai_set_sysclk()` to require `clk_id == 0`,
  `dir == SND_SOC_CLOCK_IN`, and `freq == aw88261->tdm_sysclk`. This yields
  6.144 MHz for four slots and 12.288 MHz for eight slots.

Do not import unrelated upstream volume, profile, or probe refactors.

- [ ] **Step 9: Update firmware and kernel package sources**

In the firmware APKBUILD:

- Set `pkgrel=15`; this supersedes the initial r14 graph source after the
  runtime route-name correction.
- Add `module_tdm.m4` to `source`.
- Keep `audioreach-audio-if-tokens.m4` because it defines the host parser token numbers.
- Remove `module_audio_if.m4` from `source` because the topology no longer imports it.
- Remove the obsolete `module_audio_if.m4` checksum entry.
- Replace the changed M4 checksums and add the `module_tdm.m4` checksum. Generate
  the exact digests with:

```bash
sha512sum \
  device/testing/firmware-xiaomi-mondrian/subgraph-device-tdm-playback.m4 \
  device/testing/firmware-xiaomi-mondrian/module_tdm.m4
```

Regenerate `linux-local.tar.gz`:

```bash
tar --exclude-vcs --exclude='*.o' --exclude='*.cmd' --exclude='*.ko' \
  --exclude='*.dtb' --exclude='*.dtbo' --exclude='.config' \
  --exclude='Module.symvers' --exclude='System.map' --exclude='vmlinux' \
  -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux -czf \
  /home/kreato/Sources/mondrian/mondrian/pmaports/device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz .
sha512sum device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz
```

Set the kernel APKBUILD to `pkgrel=19` and replace only the archive checksum
with the printed digest.

- [ ] **Step 10: Run static and topology tests**

```bash
mkdir -p /tmp/opencode/mondrian-audioreach-topology
tar -xzf /home/kreato/.local/var/pmbootstrap/cache_distfiles/audioreach-topology-d7a5e9d80ad18a7a6844eeb32cacbdeea0e7e677.tar.gz \
  -C /tmp/opencode/mondrian-audioreach-topology --strip-components=1
device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh
sh -n device/testing/firmware-xiaomi-mondrian/APKBUILD
sh -n device/testing/linux-postmarketos-qcom-sm8450/APKBUILD
NIX_PATH=nixpkgs=/nix/store/fafnljsz5sckb1vzpns5dc2l6z4xkakm-source nix-shell -p alsa-utils coreutils m4 --run 'm4 -I device/testing/firmware-xiaomi-mondrian -I /tmp/opencode/mondrian-audioreach-topology device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4 > /tmp/Xiaomi-Mondrian-legacy.conf && rg "0x0700100E" /tmp/Xiaomi-Mondrian-legacy.conf && ! rg "0x0700117C" /tmp/Xiaomi-Mondrian-legacy.conf && alsatplg -c /tmp/Xiaomi-Mondrian-legacy.conf -o /tmp/Xiaomi-Mondrian-legacy.bin && od -An -tx1 -v /tmp/Xiaomi-Mondrian-legacy.bin | tr -d " \n" > /tmp/Xiaomi-Mondrian-legacy.hex && rg "0e100007" /tmp/Xiaomi-Mondrian-legacy.hex && ! rg "7c110007" /tmp/Xiaomi-Mondrian-legacy.hex'
```

Expected: all checks pass; generated topology contains the legacy sink ID and
no Audio IF sink ID.

- [ ] **Step 11: Build and deploy the r19/r15 graph-open checkpoint**

Have the user run:

```bash
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build linux-postmarketos-qcom-sm8450 --force
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build firmware-xiaomi-mondrian --force
```

Install the exact r19 kernel APK and r15 topology APK:

```bash
scp /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r19.apk \
  /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/firmware-xiaomi-mondrian-tplg-1-r15.apk \
  user@172.16.42.1:/tmp/
ssh user@172.16.42.1 'sudo apk add --allow-untrusted --force-overwrite /tmp/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r19.apk /tmp/firmware-xiaomi-mondrian-tplg-1-r15.apk'
scp user@172.16.42.1:/boot/sm8475-xiaomi-mondrian.dtb /tmp/mondrian-legacy-r19.dtb
NIX_PATH=nixpkgs=/nix/store/fafnljsz5sckb1vzpns5dc2l6z4xkakm-source nix-shell -p dtc --run "dtc -I dtb -O dts /tmp/mondrian-legacy-r19.dtb > /tmp/mondrian-legacy-r19.dts && test \$(rg -c 'dai-tdm-slot-num = <0x04>;' /tmp/mondrian-legacy-r19.dts) -eq 2 && ! rg 'dai@38' /tmp/mondrian-legacy-r19.dts"
scp user@172.16.42.1:/boot/boot.img /tmp/mondrian-legacy-open-r19-boot.img
ssh user@172.16.42.1 'sudo reboot bootloader'
timeout 90 bash -c 'until fastboot devices | rg -q "[[:space:]]fastboot$"; do sleep 1; done'
fastboot getvar current-slot
fastboot flash boot_b /tmp/mondrian-legacy-open-r19-boot.img
fastboot reboot
```

Expected: the decoded DTB has two four-slot properties and no external clock
child; `current-slot: b`; only `boot_b` is written.

- [ ] **Step 12: Run the minimal legacy graph-open probe**

```bash
ssh user@172.16.42.1 'sudo dmesg -C; amixer -c 0 sset "TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1" on >/dev/null; timeout 3 aplay -D hw:0,0 --period-size=480 --buffer-size=1920 -f S16_LE -r 48000 -c 2 /dev/zero >/tmp/aplay-legacy-open.log 2>&1; cat /tmp/aplay-legacy-open.log; sudo dmesg | grep -E "DSP returned error|Failed to open graph|Failed to set media format|Failed to prepare|ASoC error"'
```

Expected checkpoint result: no DSP error for `APM_CMD_GRAPH_OPEN` (`0x01001000`). A graph-prepare failure caused by the intentionally unconfigured endpoint is acceptable and must be retained exactly. If graph open rejects `MODULE_ID_TDM_SINK`, stop the plan.

### Task 3: Configure The Legacy TDM Endpoint And Clock

**Files:**
- Modify: `../mondrian-linux/sound/soc/qcom/qdsp6/audioreach.h:475-553,795-874`
- Modify: `../mondrian-linux/sound/soc/qcom/qdsp6/audioreach.c:148-176,1059-1129,1401-1473`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD:6,87`
- Replace: `device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz`

**Interfaces:**
- Consumes: topology-loaded fields in `struct audioreach_module`, runtime slot overrides in `struct audioreach_module_config`, and `q6apm_send_cmd_sync()`.
- Produces: `audioreach_tdm_set_media_format()` sends legacy interface, endpoint-media, frame-size, and endpoint-clock parameters as separate commands and returns the first failure.

- [ ] **Step 1: Extend the focused test for legacy payload and dispatch support**

Append:

```sh
audioreach_c="$kernel/sound/soc/qcom/qdsp6/audioreach.c"

grep -Fq '#define PARAM_ID_TDM_INTF_CFG' "$ar_h"
grep -Fq '#define PARAM_ID_TDM_LANE_CFG' "$ar_h"
grep -Fq '#define PARAM_ID_HW_INTF_CLK_CFG' "$ar_h"
grep -Fq 'struct param_id_tdm_intf_cfg' "$ar_h"
grep -Fq 'struct param_id_hw_intf_clk_cfg' "$ar_h"
grep -Fq 'audioreach_tdm_set_media_format' "$audioreach_c"
rg -q -U 'case MODULE_ID_TDM_SOURCE:\n\s*case MODULE_ID_TDM_SINK:\n\s*rc = audioreach_tdm_set_media_format' "$audioreach_c"
grep -Fq 'CLOCK_ID_TER_TDM_IBIT' "$ar_h"
grep -Fq 'CLOCK_ATTRIBUTE_INVERT_COUPLE_NO' "$audioreach_c"
```

- [ ] **Step 2: Run the test and verify RED**

Expected: non-zero exit because no legacy payload or media-format path exists.

- [ ] **Step 3: Add exact public API definitions**

Add `#include <linux/stddef.h>` beside the existing Linux includes, then add to
`audioreach.h`:

```c
#define PARAM_ID_TDM_INTF_CFG		0x0800101B
#define PARAM_ID_TDM_LANE_CFG		0x0800106A
#define PARAM_ID_HW_INTF_CLK_CFG	0x0800113C

#define CLOCK_ID_PRI_TDM_IBIT		0x200
#define CLOCK_ID_TER_TDM_IBIT		0x204
#define CLOCK_ATTRIBUTE_COUPLE_NO	0x1
#define CLOCK_ATTRIBUTE_INVERT_COUPLE_NO	0x4
#define CLOCK_ROOT_DEFAULT		0x0

struct param_id_tdm_intf_cfg {
	u32 lpaif_type;
	u32 intf_idx;
	u16 sync_src;
	u16 ctrl_data_out_enable;
	u32 slot_mask;
	u16 nslots_per_frame;
	u16 slot_width;
	u16 sync_mode;
	u16 ctrl_invert_sync_pulse;
	u16 ctrl_sync_data_delay;
	u16 reserved;
} __packed;

struct param_id_tdm_lane_cfg {
	u16 lane_mask;
	u16 reserved;
} __packed;

struct param_id_hw_intf_clk_cfg {
	u32 clock_id;
	u32 clock_freq;
	u32 clock_attri;
	u32 clock_root;
} __packed;
```

Add compile-time layout checks near these structures:

```c
static_assert(sizeof(struct param_id_tdm_intf_cfg) == 28);
static_assert(offsetof(struct param_id_tdm_intf_cfg, slot_mask) == 12);
static_assert(offsetof(struct param_id_tdm_intf_cfg, nslots_per_frame) == 16);
static_assert(offsetof(struct param_id_tdm_intf_cfg, sync_mode) == 20);
static_assert(sizeof(struct param_id_tdm_lane_cfg) == 4);
static_assert(sizeof(struct param_id_hw_intf_clk_cfg) == 16);
static_assert(offsetof(struct param_id_hw_intf_clk_cfg, clock_freq) == 4);
static_assert(offsetof(struct param_id_hw_intf_clk_cfg, clock_root) == 12);
```

- [ ] **Step 4: Add a helper that sends one endpoint parameter per command**

In `audioreach.c`, add:

```c
static int audioreach_tdm_send_param(struct q6apm_graph *graph,
				    const struct audioreach_module *module,
				    u32 param_id, const void *payload,
				    size_t payload_size)
{
	struct apm_module_param_data *param_data;
	int param_size = ALIGN(payload_size, 8);
	int size = APM_MODULE_PARAM_DATA_SIZE + param_size;
	void *p;

	struct gpr_pkt *pkt __free(kfree) =
		audioreach_alloc_apm_cmd_pkt(size, APM_CMD_SET_CFG, 0);
	if (IS_ERR(pkt))
		return PTR_ERR(pkt);

	p = (void *)pkt + GPR_HDR_SIZE + APM_CMD_HDR_SIZE;
	param_data = p;
	param_data->module_instance_id = module->instance_id;
	param_data->error_code = 0;
	param_data->param_id = param_id;
	param_data->param_size = payload_size;
	memcpy(p + APM_MODULE_PARAM_DATA_SIZE, payload, payload_size);

	return q6apm_send_cmd_sync(graph->apm, pkt, 0);
}
```

`param_size` in the APM header is the exact ABI payload length, not its aligned
storage span. The packet allocation remains 8-byte aligned and zero padded;
the four advertised sizes are 28, 12, 4, and 16 bytes respectively.

- [ ] **Step 5: Implement stock-compatible TDM configuration**

Add `audioreach_tdm_set_media_format()`:

```c
static int audioreach_tdm_set_media_format(struct q6apm_graph *graph,
				   const struct audioreach_module *module,
				   const struct audioreach_module_config *cfg)
{
	u32 slot_mask = cfg->slot_mask ?: module->slot_mask;
	u16 slots = cfg->nslots_per_frame ?: module->nslots_per_frame;
	u16 slot_width = cfg->slot_width ?: module->slot_width;
	struct param_id_tdm_intf_cfg intf_cfg = {
		.lpaif_type = module->hw_interface_type,
		.intf_idx = module->hw_interface_idx,
		.sync_src = module->sync_src,
		.ctrl_data_out_enable = module->ctrl_data_out_enable,
		.slot_mask = slot_mask,
		.nslots_per_frame = slots,
		.slot_width = slot_width,
		.sync_mode = module->sync_mode,
		.ctrl_invert_sync_pulse = module->ctrl_invert_sync_pulse,
		.ctrl_sync_data_delay = module->ctrl_sync_data_delay,
	};
	struct param_id_hw_ep_mf mf_cfg = {
		.sample_rate = cfg->sample_rate,
		.bit_width = cfg->bit_width,
		.num_channels = cfg->num_channels,
		.data_format = module->data_format,
	};
	struct param_id_fram_size_factor fs_cfg = {
		.frame_size_factor = 1,
	};
	struct param_id_hw_intf_clk_cfg clk_cfg;
	u32 clock_freq;
	int ret;

	if (!slot_mask || !slots || !slot_width || module->hw_interface_idx > 4)
		return -EINVAL;

	clock_freq = cfg->sample_rate * slots * slot_width;
	clk_cfg.clock_id = CLOCK_ID_PRI_TDM_IBIT + module->hw_interface_idx * 2;
	clk_cfg.clock_freq = clock_freq;
	clk_cfg.clock_attri = module->inv_int_bit_clk ?
		CLOCK_ATTRIBUTE_INVERT_COUPLE_NO : CLOCK_ATTRIBUTE_COUPLE_NO;
	clk_cfg.clock_root = CLOCK_ROOT_DEFAULT;

	ret = audioreach_tdm_send_param(graph, module, PARAM_ID_TDM_INTF_CFG,
					 &intf_cfg, sizeof(intf_cfg));
	if (ret) {
		dev_err(graph->dev, "failed to configure TDM interface: %d\n", ret);
		return ret;
	}

	ret = audioreach_tdm_send_param(graph, module, PARAM_ID_HW_EP_MF_CFG,
					 &mf_cfg, sizeof(mf_cfg));
	if (ret) {
		dev_err(graph->dev, "failed to configure TDM media format: %d\n", ret);
		return ret;
	}

	ret = audioreach_tdm_send_param(graph, module,
					 PARAM_ID_HW_EP_FRAME_SIZE_FACTOR,
					 &fs_cfg, sizeof(fs_cfg));
	if (ret) {
		dev_err(graph->dev, "failed to configure TDM frame size: %d\n", ret);
		return ret;
	}

	ret = audioreach_tdm_send_param(graph, module, PARAM_ID_HW_INTF_CLK_CFG,
					 &clk_cfg, sizeof(clk_cfg));
	if (ret)
		dev_err(graph->dev, "failed to configure TDM clock %#x at %u Hz: %d\n",
			clk_cfg.clock_id, clk_cfg.clock_freq, ret);

	return ret;
}
```

The exact Mondrian values generated by this function are clock ID `0x204`, frequency `6144000`, attribute `4`, and root `0`.

- [ ] **Step 6: Dispatch legacy TDM modules to the new path**

Add to `audioreach_set_media_format()`:

```c
	case MODULE_ID_TDM_SOURCE:
	case MODULE_ID_TDM_SINK:
		rc = audioreach_tdm_set_media_format(graph, module, cfg);
		break;
```

- [ ] **Step 7: Run focused checks and compile the changed objects**

```bash
device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh
```

Regenerate the archive and print its new checksum:

```bash
tar --exclude-vcs --exclude='*.o' --exclude='*.cmd' --exclude='*.ko' \
  --exclude='*.dtb' --exclude='*.dtbo' --exclude='.config' \
  --exclude='Module.symvers' --exclude='System.map' --exclude='vmlinux' \
  -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux -czf \
  /home/kreato/Sources/mondrian/mondrian/pmaports/device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz .
sha512sum device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz
```

Set the kernel APKBUILD to `pkgrel=20` and replace only the archive checksum
with the printed digest.

Have the user run:

```bash
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build linux-postmarketos-qcom-sm8450 --force
```

Expected: r20 package builds without compiler warnings from the changed files.

- [ ] **Step 8: Deploy r20 and run the full legacy endpoint probe**

Install r20, regenerate `/boot/boot.img`, verify the DTB still has four slots
and no `dai@38`, then flash only `boot_b`:

```bash
scp /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r20.apk user@172.16.42.1:/tmp/
ssh user@172.16.42.1 'sudo apk add --allow-untrusted --force-overwrite /tmp/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r20.apk'
scp user@172.16.42.1:/boot/boot.img /tmp/mondrian-legacy-full-r20-boot.img
ssh user@172.16.42.1 'sudo reboot bootloader'
timeout 90 bash -c 'until fastboot devices | rg -q "[[:space:]]fastboot$"; do sleep 1; done'
fastboot getvar current-slot
fastboot flash boot_b /tmp/mondrian-legacy-full-r20-boot.img
fastboot reboot
```

```bash
ssh user@172.16.42.1 'sudo dmesg -C; amixer -c 0 sset "TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1" on >/dev/null; timeout 3 aplay -D hw:0,0 --period-size=480 --buffer-size=1920 -f S16_LE -r 48000 -c 2 /dev/zero >/tmp/aplay-legacy-full.log 2>&1; cat /tmp/aplay-legacy-full.log; sudo dmesg | grep -E "DSP returned error|failed to configure TDM|Failed to open graph|Failed to prepare|Failed to start|ASoC error|aw88261"'
```

Expected: no DSP or ASoC error; the graph opens, configures, prepares, and starts. If any TDM parameter is rejected, stop and retain the named stage from the new error message.

### Task 4: Verify Stereo Speaker Output

**Files:**
- No source changes unless Task 3 reaches graph start without functional lane-0 output.

**Interfaces:**
- Consumes: r20 kernel, r15 topology, active legacy TDM graph, AW88261 codec pair.
- Produces: evidence of audible stereo playback and correct top/bottom slot routing, or a precise post-graph blocker.

- [ ] **Step 1: Verify amplifier startup and hardware PCM stability**

```bash
ssh user@172.16.42.1 'sudo dmesg -C; amixer -c 0 sset "TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1" on >/dev/null; timeout 5 speaker-test -D hw:0,0 -r 48000 -F S16_LE -c 2 -t sine -f 440 -l 1 >/tmp/speaker-stereo.log 2>&1; cat /tmp/speaker-stereo.log; sudo dmesg | grep -E "aw88261|DSP returned error|ASoC error|underrun|xrun|failed"'
```

Expected: both amplifiers report successful startup, no DSP/ASoC/xrun error appears, and both speakers are audible.

- [ ] **Step 2: Verify left and right routing separately**

```bash
ssh user@172.16.42.1 'speaker-test -D hw:0,0 -r 48000 -F S16_LE -c 2 -t sine -f 440 -s 1 -l 1'
ssh user@172.16.42.1 'speaker-test -D hw:0,0 -r 48000 -F S16_LE -c 2 -t sine -f 660 -s 2 -l 1'
```

Expected: each command activates exactly one physical speaker/channel. Record which physical speaker corresponds to each ALSA channel.

- [ ] **Step 3: Classify a post-graph failure without guessing**

If Task 3 has no DSP errors but Task 4 has no sound, use this decision table:

```text
AW88261 reports missing PLL/BCLK and graph started:
  Proceed to Task 5 lane configuration.

AW88261 starts successfully but no sound:
  Stop; retain codec status and investigate slot/channel routing separately.

Graph start occurs only after AW88261 startup fails:
  Stop; design a TDM-only prepare/start timing change before editing code.
```

Do not combine lane, routing, and graph-start timing changes in one build.

### Task 5: Add Explicit Lane 0 Configuration Only If Required

**Entry condition:** Execute only when Task 3 reaches graph start without DSP errors and Task 4 reports missing interface clock/lane activity from the AW88261 status. Otherwise mark this task not needed.

**Files:**
- Modify: `../mondrian-linux/sound/soc/qcom/qdsp6/audioreach.c:audioreach_tdm_set_media_format()`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD:6,87`
- Replace: `device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz`

**Interfaces:**
- Consumes: `module->active_lane_mask = 0x1` from the topology.
- Produces: one additional `PARAM_ID_TDM_LANE_CFG` command between interface and media-format configuration.

- [ ] **Step 1: Add a failing lane-command test**

Append:

```sh
rg -q -U 'PARAM_ID_TDM_LANE_CFG,\n\s*&lane_cfg, sizeof\(lane_cfg\)' "$audioreach_c"
```

Run the focused script and expect non-zero exit.

- [ ] **Step 2: Send the explicit lane mask**

In `audioreach_tdm_set_media_format()`, define:

```c
	struct param_id_tdm_lane_cfg lane_cfg = {
		.lane_mask = module->active_lane_mask,
	};
```

After successful `PARAM_ID_TDM_INTF_CFG` and before media format, add:

```c
	if (lane_cfg.lane_mask) {
		ret = audioreach_tdm_send_param(graph, module, PARAM_ID_TDM_LANE_CFG,
						 &lane_cfg, sizeof(lane_cfg));
		if (ret) {
			dev_err(graph->dev, "failed to configure TDM lane mask %#x: %d\n",
				lane_cfg.lane_mask, ret);
			return ret;
		}
	}
```

- [ ] **Step 3: Build and deploy the isolated r21 lane checkpoint**

Run the focused test and regenerate the archive:

```bash
device/testing/linux-postmarketos-qcom-sm8450/test-legacy-tdm-proof.sh
tar --exclude-vcs --exclude='*.o' --exclude='*.cmd' --exclude='*.ko' \
  --exclude='*.dtb' --exclude='*.dtbo' --exclude='.config' \
  --exclude='Module.symvers' --exclude='System.map' --exclude='vmlinux' \
  -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux -czf \
  /home/kreato/Sources/mondrian/mondrian/pmaports/device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz .
sha512sum device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz
```

Set `pkgrel=21`, replace the archive checksum, and have the user run:

```bash
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build linux-postmarketos-qcom-sm8450 --force
```

Deploy the exact package and flash only `boot_b`:

```bash
scp /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r21.apk user@172.16.42.1:/tmp/
ssh user@172.16.42.1 'sudo apk add --allow-untrusted --force-overwrite /tmp/linux-postmarketos-qcom-sm8450-7.1.0_rc7-r21.apk'
scp user@172.16.42.1:/boot/boot.img /tmp/mondrian-legacy-lane-r21-boot.img
ssh user@172.16.42.1 'sudo reboot bootloader'
timeout 90 bash -c 'until fastboot devices | rg -q "[[:space:]]fastboot$"; do sleep 1; done'
fastboot getvar current-slot
fastboot flash boot_b /tmp/mondrian-legacy-lane-r21-boot.img
fastboot reboot
```

- [ ] **Step 4: Repeat the bounded Task 3 and Task 4 probes**

Expected: no parameter rejection and both speakers become audible. If lane configuration is rejected or does not change the observed hardware status, stop and roll back to the retained r20 boot image.

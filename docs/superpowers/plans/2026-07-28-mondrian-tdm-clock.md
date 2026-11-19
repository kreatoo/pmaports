# Mondrian TDM Clock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the LPASS Audio IF2 bit clock before Mondrian configures its tertiary TDM AW88261 playback graph.

**Architecture:** The generic Qualcomm AudioReach TDM implementation is already present in the kernel. Add a single Mondrian DT child for backend DAI 56 that supplies its `bclk` from the existing q6prm Audio IF2 clock provider; the SM8450 machine driver then derives and enables 12.288 MHz from the active 48 kHz, 8-slot, 32-bit PCM parameters.

**Tech Stack:** Linux kernel devicetree, Qualcomm q6prm clock controller, ASoC AudioReach, pmbootstrap, fastboot, ALSA.

## Global Constraints

- Do not use git commands, worktrees, staging, or commits.
- Use `/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap` when pmbootstrap is required.
- User runs host sudo-required build commands; phone SSH user is `user`, then use `sudo`.
- Flash only active-slot `boot_b`; do not flash `userdata` or `vendor_boot`.
- Keep the change limited to Mondrian stereo TDM playback; do not change generic AudioReach code or DSP firmware.

---

### Task 1: Add The Mondrian Audio IF2 Backend Clock

**Files:**
- Modify: `mondrian-linux/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts:1006-1009`
- Modify: `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD:6,87`
- Replace: `device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz`

**Interfaces:**
- Consumes: `q6apmbedai` with `#address-cells = <1>` and `#size-cells = <0>`; `q6prmcc` with two clock cells; `TERTIARY_TDM_RX_0`; `LPASS_CLK_ID_INTF2_IBIT`; `LPASS_CLK_ATTRIBUTE_COUPLE_NO`.
- Produces: A backend DAI child with `reg = <56>` and a `bclk` usable by `q6i2s_set_sysclk()`.

- [ ] **Step 1: Capture the pre-change DT validation failure**

Run from `mondrian-linux`:

```bash
rg -n 'dai@38' arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts
```

Expected: no output, confirming the tertiary TDM backend has no clock child.

- [ ] **Step 2: Add the backend DAI clock child**

Inside the existing `&q6apmbedai` node, after its address and size-cell declarations, add exactly:

```dts
	dai@38 {
		reg = <TERTIARY_TDM_RX_0>;
		clocks = <&q6prmcc LPASS_CLK_ID_INTF2_IBIT
			  LPASS_CLK_ATTRIBUTE_COUPLE_NO>;
		clock-names = "bclk";
	};
```

Do not create a second TDM link, alter the existing slot properties, or add an EBIT clock. The existing TDM setup only calls `snd_soc_dai_set_sysclk()` with `LPAIF_MI2S_BCLK`.

- [ ] **Step 3: Verify the static DT contract**

Run from the repository root:

```bash
rg -n -U 'dai@38 \{\n\s*reg = <TERTIARY_TDM_RX_0>;\n\s*clocks = <&q6prmcc LPASS_CLK_ID_INTF2_IBIT\n\s*LPASS_CLK_ATTRIBUTE_COUPLE_NO>;\n\s*clock-names = "bclk";' mondrian-linux/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts
```

Expected: one match covering the new `dai@38` node.

- [ ] **Step 4: Regenerate the packaged kernel source archive**

The APKBUILD extracts `linux-local.tar.gz`; editing the sibling
`mondrian-linux` directory alone cannot affect the package. Recreate the
archive from that directory while excluding VCS and build output:

```bash
tar --exclude-vcs --exclude='*.o' --exclude='*.cmd' --exclude='*.ko' \
  --exclude='*.dtb' --exclude='*.dtbo' --exclude='.config' \
  --exclude='Module.symvers' --exclude='System.map' --exclude='vmlinux' \
  -C /home/kreato/Sources/mondrian/mondrian/mondrian-linux -czf \
  /home/kreato/Sources/mondrian/mondrian/pmaports/device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz .
```

Expected: the archive contains `./arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts` with the new `dai@38` node and contains no `*.o` file.

- [ ] **Step 5: Bump the package release and source checksum**

In `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD`, change:

```sh
pkgrel=16
```

to:

```sh
pkgrel=17
```

Then calculate the archive checksum:

```bash
sha512sum device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz
```

Replace only the checksum preceding `linux-local.tar.gz` in `sha512sums` with
the command output's 128-character digest. Keep the filename and other source
checksums unchanged.

- [ ] **Step 6: Verify archive and package metadata**

Run from the repository root:

```bash
tar -xOf device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz ./arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts | rg -A4 'dai@38'
test "$(sha512sum device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz | cut -d' ' -f1)" = "$(awk '/linux-local\.tar\.gz$/ { print $1 }' device/testing/linux-postmarketos-qcom-sm8450/APKBUILD)"
grep -Fqx 'pkgrel=17' device/testing/linux-postmarketos-qcom-sm8450/APKBUILD
```

Expected: the extracted source includes the exact clock node, the checksum matches, and `pkgrel` is 17.

- [ ] **Step 7: Build the kernel package and validate DT compilation**

Run the required package build:

```bash
/nix/store/4v2bvq07jg8lca9ljbchf1apv25wb7sv-pmbootstrap-3.10.3/bin/pmbootstrap build linux-postmarketos-qcom-sm8450 --force
```

Expected: the kernel package build completes and the generated APK contains an updated Mondrian DTB. If host permissions are needed, have the user run the command rather than changing ownership or using an alternate pmbootstrap executable.

### Task 2: Deploy And Test The Clocked TDM Graph

**Files:**
- Read: `device/testing/linux-postmarketos-qcom-sm8450/APKBUILD`
- Read: `device/testing/firmware-xiaomi-mondrian/30-initramfs-firmware.files`

**Interfaces:**
- Consumes: rebuilt `linux-postmarketos-qcom-sm8450` APK, the already installed r13 Mondrian DSP/initramfs packages, `/boot/boot.img`, and fastboot slot `b`.
- Produces: a booted Mondrian kernel whose Audio IF2 `bclk` is enabled before graph media-format configuration.

- [ ] **Step 1: Install the rebuilt kernel APK**

Identify the newly built APK in the pmbootstrap `edge/aarch64` package directory and transfer it to the device:

```bash
scp /home/kreato/.local/var/pmbootstrap/packages/edge/aarch64/linux-postmarketos-qcom-sm8450-*.apk user@172.16.42.1:/tmp/
ssh user@172.16.42.1 'sudo apk add --allow-untrusted --force-overwrite /tmp/linux-postmarketos-qcom-sm8450-*.apk'
```

Expected: `postmarketos-mkinitfs` and boot deployment regenerate `/boot/boot.img` without an error.

- [ ] **Step 2: Validate the installed DTB before flashing**

Copy the deployed DTB to the host and decode it with `dtc`:

```bash
scp user@172.16.42.1:/boot/sm8475-xiaomi-mondrian.dtb /tmp/mondrian-tdm-clock.dtb
NIX_PATH=nixpkgs=/nix/store/fafnljsz5sckb1vzpns5dc2l6z4xkakm-source nix-shell -p dtc --run 'dtc -I dtb -O dts /tmp/mondrian-tdm-clock.dtb | rg -A4 "dai@38"'
```

The decoded Mondrian DTB must include the following properties in the `q6apmbedai` child for DAI 56:

```text
reg = <0x38>;
clock-names = "bclk";
```

Expected: the child binds its `bclk` to the q6prm Audio IF2 IBIT clock. Do not flash if the child is absent.

- [ ] **Step 3: Flash only `boot_b`**

```bash
scp user@172.16.42.1:/boot/boot.img /tmp/mondrian-tdm-clock-boot.img
ssh user@172.16.42.1 'sudo reboot bootloader'
fastboot flash boot_b /tmp/mondrian-tdm-clock-boot.img
fastboot reboot
```

Expected: fastboot reports a successful write to `boot_b`; no other partition is flashed.

- [ ] **Step 4: Run one bounded hardware PCM probe**

After SSH becomes available, clear the kernel log, enable the existing topology mixer route, and perform one fixed-parameter playback setup:

```bash
ssh user@172.16.42.1 'cat /sys/class/remoteproc/remoteproc1/firmware; sudo dmesg -C; amixer -c 0 sset "TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1" on >/dev/null; timeout 3 aplay -D hw:0,0 --period-size=480 --buffer-size=1920 -f S16_LE -r 48000 -c 2 /dev/zero >/tmp/aplay-tdm-clock.log 2>&1; cat /tmp/aplay-tdm-clock.log; sudo dmesg | grep -E "q6prm|DSP returned error|Failed to set media format|ASoC error" | tail -20'
```

Expected: `qcom/sm8475/xiaomi/mondrian/adsp.mdt` is active; the probe has no `Failed to set media format`, no `DSP returned error`, and no `ASoC error`; both AW88261 speakers produce audio.

- [ ] **Step 5: Record a negative result precisely if the DSP still rejects the graph**

If setup fails, retain the exact `aplay` output and the final 20 filtered `dmesg` lines. Classify this as an Audio IF graph ABI/configuration mismatch only after confirming the DTB contains `dai@38` and the log contains no q6prm clock-acquisition error.

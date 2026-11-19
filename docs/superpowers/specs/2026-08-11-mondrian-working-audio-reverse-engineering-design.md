# Mondrian Working Audio Reverse-Engineering Design

## Goal

Identify any software difference that explains why the known-good LineageOS build drives Mondrian's bottom AW88261 amplifier while mainline r24 remains silent.

## Known State

- Mainline r24 sends the exact stock AudioReach tertiary-TDM interface and lane payload extracted from Mondrian ACDB.
- Mainline r24 preserves the exact per-channel Music profile registers extracted from `aw882xx_acf.bin`.
- During isolated channel-1 playback, amplifier `0x35` reports stable clocks and active state but near-zero output sense.
- Correcting PID 2113 initialization, codec framing, TX restore, and MPD behavior did not produce bottom output.
- Runtime GPIO and pinctrl state matches the production board description.
- The supplied LineageOS build is known to produce working speaker output on this device.

## Reference Artifacts

Local known-good build artifacts:

- `/home/kreato/Downloads/boot.img`
- `/home/kreato/Downloads/vendor_boot.img`
- `/home/kreato/Downloads/dtbo.img`
- `/home/kreato/Downloads/build-manifest.xml`

Manifest-pinned source revisions:

- `LineageOS/android_kernel_xiaomi_sm8450` at `e682ed2de56fd2841ef35741c4d0f03599ffd561`
- `LineageOS/android_kernel_xiaomi_sm8450-modules` at `ae45c06de3317b5ffcdf47bb9ccf35f7126d5933`
- `LineageOS/android_kernel_xiaomi_sm8450-devicetrees` at `895b75b6cc027e069960554c329e94b3f4b0f825`
- `LineageOS/android_device_xiaomi_mondrian` at `0bb28ea96d3adb7ff72064cc1428ad1520799ada`
- `LineageOS/android_device_xiaomi_sm8450-common` at `56a76e44de268ffacdee822f266708bcb4234ed6`

## Approach

### Exact Source First

Inspect the manifest-pinned source revisions before disassembling binaries. Recover the complete known-good control path for:

- AW88261 probe and hardware initialization;
- reset and power sequencing;
- ACF/profile loading;
- DAI format and TDM slot configuration;
- calibration and EFUSE handling;
- start, mute, boost, feedback, and shutdown sequencing;
- tertiary-TDM interface, lane, slot, clock, and channel configuration;
- Mondrian-specific audio routes and mixer controls.

Record register writes, masks, values, delays, conditions, and execution order. Distinguish values loaded from ACF from runtime overrides.

### Binary Verification

Unpack copies of the supplied images under `/tmp/opencode`; do not alter the originals. Use `vendor_boot.img` first to identify packaged modules, module lists, and vendor ramdisk configuration. Use `boot.img` for the kernel image and configuration. Decompile only code that is absent from, or inconsistent with, the manifest-pinned source.

Verify that module names, symbols, strings, source revisions, and build configuration agree with the source analysis. If the Awinic driver is not present in either image, identify the required populated `vendor_dlkm.img` or installed module tree rather than inferring behavior from unrelated code.

### DTBO and Audio Configuration

Decompile `dtbo.img` and compare its selected Mondrian overlay against the production DTBO already analyzed. Confirm amplifier addresses, channels, reset/interrupt GPIOs, pinctrl, supplies, DAI links, and any Awinic-specific properties.

Inspect the exact LineageOS device and common-device audio configuration for PAL/AGM route selection, backend names, channel allocation, and any mixer action not represented in the ACDB payload.

## Comparison Output

Produce one evidence table with these columns:

- stage and execution order;
- known-good source or binary reference;
- register/parameter and value;
- mainline r24 behavior;
- difference classification;
- expected observable effect.

Classify each difference as one of:

- already equivalent;
- irrelevant to bottom playback;
- configuration-only;
- plausible silence cause;
- requires runtime confirmation.

## Decision Gate

Do not modify the phone, kernel, topology, or ACF unless the comparison identifies a concrete mismatch supported by the known-good source or binary. Do not run another audible test without explicit approval.

If a mismatch is found, first add a focused regression that expresses the known-good behavior, then make the smallest production change. The expected register or DSP readback must be stated before deployment.

## Success Criteria

The investigation succeeds when it produces either:

1. A specific missing value or sequence, with an exact known-good source/binary reference and a testable mainline correction; or
2. A complete equivalence finding that places the remaining fault boundary at physical DATA1 delivery, amplifier hardware, or the bottom speaker/load.

## Safety

- Keep the phone profile off, route off, and both hardware volumes at `720` during static analysis.
- Do not flash any supplied Android image.
- Do not modify files under `/home/kreato/Downloads`.
- Extract only into `/tmp/opencode`.
- Do not use git commands, staging, or commits.
- Never flash `userdata` or `vendor_boot`; any later mainline deployment remains limited to verified `boot_b`.

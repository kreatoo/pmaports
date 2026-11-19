# Mondrian TDM Clock Design

## Goal

Enable the existing AudioReach tertiary TDM playback graph to request its
mandatory LPASS Audio IF bit clock before configuring the AW88261 speaker
link.

## Scope

This change is limited to Xiaomi Mondrian stereo speaker playback. It does not
modify generic AudioReach code, add other TDM ports, or change DSP firmware.

## Architecture

The kernel already contains Qualcomm's AudioReach TDM DAI operations, topology
handling, Audio IF clock definitions, common TDM-slot helpers, and the SM8450
machine driver's TDM `hw_params` flow. That flow reads Mondrian's standard
`dai-tdm-slot-*` properties, derives the bit clock, and calls
`snd_soc_dai_set_sysclk()` for the CPU DAI.

`q6apm-lpass-dais` only obtains backend clocks from child nodes of
`q6apmbedai`. Mondrian has no child for `TERTIARY_TDM_RX_0`, so the CPU DAI has
no `bclk` to enable and the Audio IF graph is configured without its clock.

Add one `dai@38` child under `q6apmbedai` in
`arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts`:

```dts
dai@38 {
	reg = <TERTIARY_TDM_RX_0>;
	clocks = <&q6prmcc LPASS_CLK_ID_INTF2_IBIT
		  LPASS_CLK_ATTRIBUTE_COUPLE_NO>;
	clock-names = "bclk";
};
```

`TERTIARY_TDM_RX_0` is DAI ID 56 (`0x38`). Audio IF interface index 2 uses
`LPASS_CLK_ID_INTF2_IBIT`. The existing machine driver computes and enables a
12.288 MHz bit clock from 48 kHz x 8 slots x 32 bits before AudioReach sends
the interface configuration to the DSP.

## Data Flow

```text
PCM hw_params
-> SM8450 machine TDM setup
-> q6apmbedai dai@38 bclk request through q6prmcc
-> Audio IF2 IBIT enabled at 12.288 MHz
-> AudioReach Audio IF configuration
-> tertiary TDM pins
-> AW88261 top and bottom amplifiers
```

## Failure Handling

- A missing or malformed clock phandle fails DT compilation or backend clock
  acquisition rather than silently selecting another interface.
- A q6prm clock request failure is returned from `snd_soc_dai_set_sysclk()` and
  stops stream setup before the DSP graph is configured.
- If the clock is accepted but AudioReach still rejects media format setup,
  retain the exact DSP response as evidence that the remaining issue is a DSP
  ABI or graph-configuration mismatch, not a missing clock.

## Validation

1. Compile the edited Mondrian DTB as part of the kernel package build.
2. Verify the deployed DTB contains `dai@38`, `LPASS_CLK_ID_INTF2_IBIT`, and
   `clock-names = "bclk"` in its decoded representation.
3. Boot the rebuilt `boot_b` image and confirm the Mondrian ADSP loads.
4. Route `MultiMedia1` to `TERTIARY_TDM_RX_0` and run one fixed-parameter
   48 kHz stereo PCM probe.
5. Capture the q6prm clock request and AudioReach result from `dmesg`; success
   requires no AudioReach media-format error and audible stereo playback.

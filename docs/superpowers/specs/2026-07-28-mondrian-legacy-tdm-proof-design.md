# Mondrian Legacy TDM Proof Design

## Goal

Produce the shortest evidence-driven path to stereo speaker playback on Xiaomi
Mondrian by using the legacy AudioReach TDM endpoint implemented by the stock
ADSP firmware.

## Scope

This proof covers `MultiMedia1` playback through `TERTIARY_TDM_RX_0` to the two
AW88261 amplifiers. It does not add capture, other TDM ports, headset audio,
Bluetooth audio, a generic legacy TDM framework for other boards, Android
PAL/AGM userspace, or a direct AP-owned QAIF driver.

## Evidence And Decision

The current topology uses the newer QAIF Audio IF sink
`MODULE_ID_AUDIO_IF_SINK` (`0x0700117C`) and externally requests Audio IF2
clock resource `0x504`. Mondrian's stock ADSP rejects both the PRM clock
request and graph open.

The stock ADSP image contains the legacy AudioReach TDM sink and source module
IDs, including `MODULE_ID_TDM_SINK` (`0x0700100E`), but does not contain the
newer Audio IF sink ID. Qualcomm's public legacy TDM API provides the required
slot, framing, lane, media-format, and endpoint-clock parameters. Stock
Mondrian configuration evidence also uses tertiary TDM clock ID `0x204`, not
Audio IF2 clock ID `0x504`.

Therefore the proof will retain the existing GPR/APM AudioReach architecture
and replace only its unsupported endpoint ABI. Porting Android's complete
PAL/AGM stack and implementing direct AP ownership of SM8450 QAIF are both out
of scope because they introduce substantially more undocumented components.

## Architecture

The work is deliberately staged so each DSP boundary is proven before adding
the next parameter group.

1. Correct graph-open error propagation in `q6apm.c`. A rejected graph is
   removed from the IDR and freed without issuing `GRAPH_CLOSE`.
2. Define the legacy TDM sink/source IDs and payload structures used by the
   public AudioReach PCM/TDM and hardware-clock APIs.
3. Teach the topology parser and media-format dispatcher to recognize the
   legacy TDM endpoint.
4. Replace the Mondrian Audio IF sink topology module with a legacy TDM sink.
5. Verify that a minimal graph containing the legacy sink opens before adding
   its runtime configuration.
6. Configure tertiary TDM framing, media format, frame-size factor, and
   endpoint-owned clocking. Add explicit lane configuration only if the
   single-lane default proves insufficient.
7. Remove the unsupported external Audio IF2 `0x504` clock vote from the
   Mondrian backend DAI.

## Components

### Graph Lifecycle

`sound/soc/qcom/qdsp6/q6apm.c` must return the result of
`APM_CMD_GRAPH_OPEN`. On failure it removes the graph from `graph_idr`, frees
the graph packet and graph object, and returns an error pointer. It must not
send graph management commands for a graph that never opened.

A dedicated graph-lifecycle mutex serializes graph lookup, creation, open,
reference acquisition, and final release. An IDR entry cannot be consumed by a
second caller while its graph-open command is pending, and final release cannot
race a new reference acquisition.

This correctness fix is required for the proof because the existing code
ignores graph-open failure and produces misleading secondary set-config and
graph-close errors.

### Legacy TDM Endpoint

`sound/soc/qcom/qdsp6/audioreach.h` and `audioreach.c` gain only the legacy
TDM definitions required for playback:

- `MODULE_ID_TDM_SINK = 0x0700100E`
- `MODULE_ID_TDM_SOURCE = 0x0700100F`, defined for ABI completeness but not
  instantiated by Mondrian
- `PARAM_ID_TDM_INTF_CFG = 0x0800101B`
- `PARAM_ID_TDM_LANE_CFG = 0x0800106A`
- `PARAM_ID_HW_INTF_CLK_CFG = 0x0800113C`

The playback configuration sends parameters in this order and stops on the
first error:

1. TDM interface configuration
2. Hardware endpoint media format
3. Hardware endpoint frame-size factor
4. Hardware interface clock configuration

`PARAM_ID_TDM_LANE_CFG` is not sent in the first proof because Qualcomm's API
defines it as optional for a single active lane. If graph configuration and
start succeed but lane 0 remains inactive, lane mask `0x1` is added as one
separate diagnostic checkpoint.

The implementation uses packed payloads with compile-time size checks against
the public AudioReach API layout.

### Topology

The Mondrian topology instantiates `MODULE_ID_TDM_SINK` while preserving the
existing stream graph, logger, mixer, DAI ID, and routing. Host-side topology
tokens carry the legacy interface values; the DSP receives only the legacy
module and parameter ABI.

The first device package intentionally contains a minimal legacy sink graph so
graph-open acceptance can be observed independently. Runtime parameter support
is added only after that checkpoint succeeds.

### Board Configuration

The proof matches the known stock tertiary TDM configuration:

| Field | Value |
|---|---:|
| LPASS type | `0` |
| Interface index | `2` |
| Sync source | internal (`1`) |
| Data output enable | disabled (`0`) |
| Active slots | `0x3` |
| Slots per frame | `4` |
| Slot width | `32` bits |
| Sync mode | short one-bit (`0`) |
| Sync polarity | normal (`0`) |
| Data delay | one BCLK (`1`) |
| Lane mask | lane 0 (`0x1`) |
| Sample rate | `48000` Hz |
| Sample format | signed 16-bit fixed point |
| Channels | `2` |
| Tertiary TDM clock | `0x204` |
| Bit clock | `6144000` Hz |
| Clock attribute | invert, no coupling (`4`) |
| Clock root | default (`0`) |

The CPU and both AW88261 codec DAIs use four 32-bit slots and slots 0 and 1.
Codec format remains DSP_A with normal bit-clock and frame polarity. The
current `q6apmbedai` child that externally requests Audio IF2 clock `0x504` is
removed; the legacy endpoint configures its own tertiary TDM clock.

The local AW88261 driver is extended with the focused upstream TDM register model. Its
DAI callbacks program slot count, valid slot masks, and slot-width BCLK mode,
and validate the externally supplied bit clock against the selected TDM frame.
Four-slot 6.144 MHz and prior eight-slot 12.288 MHz operation remain supported.

## Data Flow

```text
MultiMedia1 PCM
-> existing stream graph and logger
-> tertiary TDM mixer
-> legacy MODULE_ID_TDM_SINK
-> PARAM_ID_TDM_INTF_CFG and PARAM_ID_HW_INTF_CLK_CFG
-> tertiary TDM pins
-> AW88261 top and bottom amplifiers
-> speakers
```

## Failure Handling

- Graph open failure stops immediately and reports the graph-open DSP status.
- Each endpoint configuration command returns its DSP status to the caller;
  later commands are not sent after a failure.
- Failed graph objects are removed and freed without a close command.
- Device test logs retain the first rejected opcode and status as the
  authoritative failure boundary.
- A successful graph open followed by configuration failure is recorded as a
  separate checkpoint, not collapsed into a generic media-format error.
- A successful endpoint setup without amplifier startup is treated as a
  graph-start or codec timing issue, not an endpoint ABI failure.

## Validation

### Static Validation

1. Verify graph-open failure cleanup and return handling with a focused test or
   injectable command-result harness.
2. Verify legacy payload sizes, field offsets, module IDs, and parameter IDs.
3. Compile the Mondrian topology and inspect the binary for the legacy TDM sink
   ID and absence of the newer Audio IF sink ID.
4. Build the kernel and firmware packages from the regenerated source archive
   and current checksums.

### Device Checkpoints

1. Deploy the graph-lifecycle fix and minimal legacy sink topology to
   `boot_b`.
2. Run one bounded PCM setup and verify `APM_CMD_GRAPH_OPEN` succeeds. A later
   set-config failure is acceptable only at this checkpoint.
3. Add and deploy interface, media-format, and frame-size configuration;
   verify each command succeeds.
4. Add endpoint clock configuration and verify clock `0x204` is accepted at
   6.144 MHz without an external `0x504` vote.
5. Verify graph prepare/start, AW88261 startup, and absence of DSP, underrun,
   and codec errors. Add `PARAM_ID_TDM_LANE_CFG` with mask `0x1` only if this
   succeeds but lane 0 remains inactive.
6. Run one bounded stereo playback test, followed by separate left and right
   channel tests to confirm both amplifiers and slot routing.

Success requires accepted graph open/configure/prepare/start operations,
successful AW88261 startup, and audible output from both speakers.

## Deployment Safety

Only the active `boot_b` partition is flashed. `userdata` and `vendor_boot`
are never flashed. Each pre-checkpoint boot image is retained so a failed
checkpoint can be rolled back without modifying user data.

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
`                AR_TKN_U16_MODULE_CTRL_DATA_OUT_ENABLE STR(1)'
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

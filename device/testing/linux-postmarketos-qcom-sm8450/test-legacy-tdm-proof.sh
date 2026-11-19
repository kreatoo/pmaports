#!/bin/sh
set -eu

root="$(CDPATH='' cd -- "$(dirname "$0")/../../.." && pwd)"
kernel="$root/../mondrian-linux"
q6apm="$kernel/sound/soc/qcom/qdsp6/q6apm.c"
q6apm_h="$kernel/sound/soc/qcom/qdsp6/q6apm.h"
ar_h="$kernel/sound/soc/qcom/qdsp6/audioreach.h"
audioreach_c="$kernel/sound/soc/qcom/qdsp6/audioreach.c"
topology_c="$kernel/sound/soc/qcom/qdsp6/topology.c"
q6ports="$kernel/sound/soc/qcom/qdsp6/q6dsp-lpass-ports.c"
machine_c="$kernel/sound/soc/qcom/sc8280xp.c"
dts="$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
aw_c="$kernel/sound/soc/codecs/aw88261.c"
aw_h="$kernel/sound/soc/codecs/aw88261.h"
firmware="$root/device/testing/firmware-xiaomi-mondrian"
kernel_config="$root/device/testing/linux-postmarketos-qcom-sm8450/config-postmarketos-qcom-sm8450.aarch64"
kernel_archive="$root/device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz"

test -f "$q6apm"
test -f "$q6apm_h"

extract_function_from() {
	awk -v function_name="$1" '
		!found && $0 ~ ("(^|[[:space:]*])" function_name "\\(") { found = 1 }
		found {
			print
			opens = gsub(/\{/, "{")
			closes = gsub(/\}/, "}")
			depth += opens - closes
			if (opens > 0)
				started = 1
			if (started && depth == 0)
				exit
		}
	' "$2"
}

extract_function() {
	extract_function_from "$1" "$q6apm"
}

get_graph="$(extract_function q6apm_get_audioreach_graph)"
put_graph="$(extract_function q6apm_put_audioreach_graph)"
release_graph="$(extract_function q6apm_release_audioreach_graph)"
graph_open="$(extract_function q6apm_graph_open)"
graph_close="$(extract_function q6apm_graph_close)"
probe="$(extract_function apm_probe)"
alloc_pkt="$(extract_function_from __audioreach_alloc_pkt "$audioreach_c")"
alloc_apm_cmd_pkt="$(extract_function_from audioreach_alloc_apm_cmd_pkt "$audioreach_c")"
tdm_send_param="$(extract_function_from audioreach_tdm_send_param "$audioreach_c")"
tdm_set_media="$(extract_function_from audioreach_tdm_set_media_format "$audioreach_c")"
machine_tdm_hw_params="$(extract_function_from sc8280xp_tdm_hw_params "$machine_c")"
machine_hw_params="$(extract_function_from sc8280xp_snd_hw_params "$machine_c")"
codec_start="$(extract_function_from aw88261_dev_start "$aw_c")"
codec_reg_update="$(extract_function_from aw88261_dev_reg_update "$aw_c")"
codec_tx_enable="$(extract_function_from aw88261_dev_i2s_tx_enable "$aw_c")"
set_tdm_slot="$(extract_function_from aw88261_dai_set_tdm_slot "$aw_c")"
set_sysclk="$(extract_function_from aw88261_dai_set_sysclk "$aw_c")"

test -n "$get_graph"
test -n "$put_graph"
test -n "$release_graph"
test -n "$graph_open"
test -n "$graph_close"
test -n "$probe"
test -n "$alloc_pkt"
test -n "$alloc_apm_cmd_pkt"
test -n "$tdm_send_param"
test -n "$tdm_set_media"
test -n "$machine_tdm_hw_params"
test -n "$machine_hw_params"
test -n "$codec_start"
test -n "$codec_reg_update"
test -n "$codec_tx_enable"
test -n "$set_tdm_slot"
test -n "$set_sysclk"

grep -Fq 'struct mutex graph_lock;' "$q6apm_h"
printf '%s\n' "$probe" | grep -Fq 'mutex_init(&apm->graph_lock);'

printf '%s\n' "$get_graph" | rg -q -U 'mutex_lock\(&apm->graph_lock\);\n\s*\n\s*mutex_lock\(&apm->lock\);\n\s*graph = idr_find\(&apm->graph_idr, graph_id\);'
printf '%s\n' "$get_graph" | rg -q -U 'if \(graph\) \{\n\s*kref_get\(&graph->refcount\);\n\s*mutex_unlock\(&apm->graph_lock\);\n\s*return graph;\n\s*\}'
printf '%s\n' "$get_graph" | rg -q -U 'ret = q6apm_send_cmd_sync\(apm, graph->graph, 0\);\n\s*if \(ret\) \{\n\s*mutex_lock\(&apm->lock\);\n\s*idr_remove\(&apm->graph_idr, graph_id\);\n\s*mutex_unlock\(&apm->lock\);\n\s*kfree\(graph->graph\);\n\s*kfree\(graph\);\n\s*mutex_unlock\(&apm->graph_lock\);\n\s*return ERR_PTR\(ret\);\n\s*\}\n\s*\n\s*mutex_unlock\(&apm->graph_lock\);\n\s*return graph;'
! printf '%s\n' "$get_graph" | rg -q 'APM_CMD_GRAPH_CLOSE|q6apm_put_audioreach_graph'
test "$(printf '%s\n' "$get_graph" | rg -c 'mutex_lock\(&apm->graph_lock\);')" -eq 1
test "$(printf '%s\n' "$get_graph" | rg -c 'mutex_unlock\(&apm->graph_lock\);')" -eq 7

printf '%s\n' "$put_graph" | rg -q -U 'mutex_lock\(&apm->graph_lock\);\n\s*kref_put\(&graph->refcount, q6apm_release_audioreach_graph\);\n\s*mutex_unlock\(&apm->graph_lock\);'
printf '%s\n' "$release_graph" | rg -q -U 'audioreach_graph_mgmt_cmd\(graph, APM_CMD_GRAPH_CLOSE\);\n\s*\n\s*mutex_lock\(&apm->lock\);\n\s*graph = idr_remove\(&apm->graph_idr, graph->id\);\n\s*mutex_unlock\(&apm->lock\);\n\s*\n\s*kfree\(graph->graph\);\n\s*kfree\(graph\);'

printf '%s\n' "$graph_open" | grep -Fq 'q6apm_put_audioreach_graph(ar_graph);'
printf '%s\n' "$graph_close" | grep -Fq 'q6apm_put_audioreach_graph(ar_graph);'
! printf '%s\n' "$graph_open" | rg -q 'kref_put\('
! printf '%s\n' "$graph_close" | rg -q 'kref_put\('
test "$(rg -c 'q6apm_put_audioreach_graph\(ar_graph\);' "$q6apm")" -eq 2
test "$(rg -c 'kref_put\(' "$q6apm")" -eq 1

rg -q '^#define\s+MODULE_ID_TDM_SINK\s+0x0700100E$' "$ar_h"
rg -q '^#define\s+MODULE_ID_TDM_SOURCE\s+0x0700100F$' "$ar_h"
rg -q -U 'case MODULE_ID_TDM_SINK:\n\s*case MODULE_ID_TDM_SOURCE:\n\s*ret = audioreach_widget_audio_if_module_load' "$topology_c"
grep -Fq '#include <linux/stddef.h>' "$ar_h"
rg -q '^#define\s+PARAM_ID_TDM_INTF_CFG\s+0x0800101B$' "$ar_h"
rg -q '^#define\s+PARAM_ID_TDM_LANE_CFG\s+0x0800106A$' "$ar_h"
rg -q '^#define\s+PARAM_ID_HW_INTF_CLK_CFG\s+0x0800113C$' "$ar_h"
rg -q '^#define\s+CLOCK_ID_PRI_TDM_IBIT\s+0x200$' "$ar_h"
rg -q '^#define\s+CLOCK_ID_TER_TDM_IBIT\s+0x204$' "$ar_h"
rg -q '^#define\s+CLOCK_ATTRIBUTE_COUPLE_NO\s+0x1$' "$ar_h"
rg -q '^#define\s+CLOCK_ATTRIBUTE_INVERT_COUPLE_NO\s+0x4$' "$ar_h"
rg -q '^#define\s+CLOCK_ROOT_DEFAULT\s+0x0$' "$ar_h"
rg -q -U 'struct param_id_tdm_intf_cfg \{\n\s*u32 lpaif_type;\n\s*u32 intf_idx;\n\s*u16 sync_src;\n\s*u16 ctrl_data_out_enable;\n\s*u32 slot_mask;\n\s*u16 nslots_per_frame;\n\s*u16 slot_width;\n\s*u16 sync_mode;\n\s*u16 ctrl_invert_sync_pulse;\n\s*u16 ctrl_sync_data_delay;\n\s*u16 reserved;\n\} __packed;' "$ar_h"
rg -q -U 'struct param_id_tdm_lane_cfg \{\n\s*u16 lane_mask;\n\s*u16 reserved;\n\} __packed;' "$ar_h"
rg -q -U 'struct param_id_hw_intf_clk_cfg \{\n\s*u32 clock_id;\n\s*u32 clock_freq;\n\s*u32 clock_attri;\n\s*u32 clock_root;\n\} __packed;' "$ar_h"
grep -Fq 'static_assert(sizeof(struct param_id_tdm_intf_cfg) == 28);' "$ar_h"
grep -Fq 'static_assert(offsetof(struct param_id_tdm_intf_cfg, slot_mask) == 12);' "$ar_h"
grep -Fq 'static_assert(offsetof(struct param_id_tdm_intf_cfg, nslots_per_frame) == 16);' "$ar_h"
grep -Fq 'static_assert(offsetof(struct param_id_tdm_intf_cfg, sync_mode) == 20);' "$ar_h"
grep -Fq 'static_assert(sizeof(struct param_id_tdm_lane_cfg) == 4);' "$ar_h"
grep -Fq 'static_assert(sizeof(struct param_id_hw_intf_clk_cfg) == 16);' "$ar_h"
grep -Fq 'static_assert(offsetof(struct param_id_hw_intf_clk_cfg, clock_freq) == 4);' "$ar_h"
grep -Fq 'static_assert(offsetof(struct param_id_hw_intf_clk_cfg, clock_root) == 12);' "$ar_h"

printf '%s\n' "$alloc_pkt" | grep -Fq 'p = kzalloc(pkt_size, GFP_KERNEL);'
printf '%s\n' "$tdm_send_param" | grep -Fq 'int param_size = ALIGN(payload_size, 8);'
printf '%s\n' "$tdm_send_param" | grep -Fq 'int size = APM_MODULE_PARAM_DATA_SIZE + param_size;'
printf '%s\n' "$tdm_send_param" | grep -Fq 'audioreach_alloc_apm_cmd_pkt(size, APM_CMD_SET_CFG, 0);'
printf '%s\n' "$tdm_send_param" | grep -Fq 'p = (void *)pkt + GPR_HDR_SIZE + APM_CMD_HDR_SIZE;'
printf '%s\n' "$tdm_send_param" | grep -Fq 'param_data->module_instance_id = module->instance_id;'
printf '%s\n' "$tdm_send_param" | grep -Fq 'param_data->error_code = 0;'
printf '%s\n' "$tdm_send_param" | grep -Fq 'param_data->param_id = param_id;'
printf '%s\n' "$tdm_send_param" | grep -Fq 'param_data->param_size = payload_size;'
! printf '%s\n' "$tdm_send_param" | grep -Fq 'param_data->param_size = param_size;'
printf '%s\n' "$tdm_send_param" | grep -Fq 'memcpy(p + APM_MODULE_PARAM_DATA_SIZE, payload, payload_size);'
printf '%s\n' "$tdm_send_param" | grep -Fq 'return q6apm_send_cmd_sync(graph->apm, pkt, 0);'
test "$(printf '%s\n' "$tdm_send_param" | rg -c 'q6apm_send_cmd_sync\(')" -eq 1

printf '%s\n' "$tdm_set_media" | grep -Fq 'u32 slot_mask = cfg->slot_mask ?: module->slot_mask;'
printf '%s\n' "$tdm_set_media" | grep -Fq 'u16 slots = cfg->nslots_per_frame ?: module->nslots_per_frame;'
printf '%s\n' "$tdm_set_media" | grep -Fq 'u16 slot_width = cfg->slot_width ?: module->slot_width;'
printf '%s\n' "$tdm_set_media" | grep -Fq 'if (!slot_mask || !slots || !slot_width || module->hw_interface_idx > 4)'
printf '%s\n' "$tdm_set_media" | grep -Fq 'clock_freq = cfg->sample_rate * slots * slot_width;'
printf '%s\n' "$tdm_set_media" | grep -Fq 'clk_cfg.clock_id = CLOCK_ID_PRI_TDM_IBIT + module->hw_interface_idx * 2;'
printf '%s\n' "$tdm_set_media" | rg -q -U 'clk_cfg\.clock_attri = module->inv_int_bit_clk \?\n\s*CLOCK_ATTRIBUTE_INVERT_COUPLE_NO : CLOCK_ATTRIBUTE_COUPLE_NO;'
printf '%s\n' "$tdm_set_media" | grep -Fq 'clk_cfg.clock_root = CLOCK_ROOT_DEFAULT;'
test "$((0x200 + 2 * 2))" -eq "$((0x204))"
test "$((48000 * 4 * 32))" -eq 6144000
rg -q -U 'DEVICE_SG_ADD\(subgraph-device-tdm-playback\.m4,[\s\S]*LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_TERTIARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,' "$firmware/Xiaomi-Mondrian.m4"
grep -Fq 'AR_TKN_U16_MODULE_CTRL_DATA_OUT_ENABLE STR(1)' "$firmware/module_tdm.m4"
grep -Fq 'NONE_IID, 0x3, 4, 32, 0, 0x2, 48000, 1, 1, 0, 1, 0, 1, 0)' "$firmware/subgraph-device-tdm-playback.m4"
printf '%s\n' "$tdm_set_media" | rg -q -U 'struct param_id_tdm_lane_cfg lane_cfg = \{\n\s*\.lane_mask = module->active_lane_mask,\n\s*\};'
test "$(printf '%s\n' "$tdm_set_media" | rg -c 'ret = audioreach_tdm_send_param\(')" -eq 5
printf '%s\n' "$tdm_set_media" | rg -q -U 'ret = audioreach_tdm_send_param\(graph, module, PARAM_ID_TDM_INTF_CFG,[\s\S]*if \(ret\) \{[\s\S]*return ret;[\s\S]*PARAM_ID_TDM_LANE_CFG,[\s\S]*&lane_cfg, sizeof\(lane_cfg\)[\s\S]*if \(ret\) \{[\s\S]*return ret;[\s\S]*ret = audioreach_tdm_send_param\(graph, module, PARAM_ID_HW_EP_MF_CFG,[\s\S]*if \(ret\) \{[\s\S]*return ret;[\s\S]*ret = audioreach_tdm_send_param\(graph, module,[\s\S]*PARAM_ID_HW_EP_FRAME_SIZE_FACTOR,[\s\S]*if \(ret\) \{[\s\S]*return ret;[\s\S]*ret = audioreach_tdm_send_param\(graph, module, PARAM_ID_HW_INTF_CLK_CFG,[\s\S]*return ret;'
rg -q -U 'case MODULE_ID_TDM_SOURCE:\n\s*case MODULE_ID_TDM_SINK:\n\s*rc = audioreach_tdm_set_media_format\(graph, module, cfg\);\n\s*break;' "$audioreach_c"
grep -Fq 'compatible = "qcom,sm8450-sndcard";' "$dts"
grep -Fq '{.compatible = "qcom,sm8450-sndcard", "sm8450"},' "$machine_c"
grep -Fq '.name = "snd-sc8280xp",' "$machine_c"
grep -Fq 'CONFIG_SND_SOC_SC8280XP=y' "$kernel_config"
printf '%s\n' "$machine_hw_params" | rg -q -U 'case PRIMARY_TDM_RX_0 \.\.\. QUINARY_TDM_TX_7:\n\s*return sc8280xp_tdm_hw_params\(substream, params\);'
printf '%s\n' "$machine_tdm_hw_params" | grep -Fq 'qcom_snd_apply_dai_tdm_slots_cfg(rtd, &cpu_cfg, &codec_cfg);'
printf '%s\n' "$machine_tdm_hw_params" | rg -q -U 'snd_soc_dai_set_sysclk\(cpu_dai, LPAIF_MI2S_BCLK, bclk_freq,\n\s*SND_SOC_CLOCK_IN\);'
printf '%s\n' "$machine_tdm_hw_params" | grep -Fq 'snd_soc_dai_set_sysclk(codec_dai, 0, bclk_freq, SND_SOC_CLOCK_IN);'
grep -Fq 'MODULE_ID_TDM_SINK' "$firmware/module_tdm.m4"
grep -Fq 'AR_MODULE_TDM_RX' "$firmware/subgraph-device-tdm-playback.m4"
! grep -Fq 'AR_MODULE_AUDIO_IF_RX' "$firmware/subgraph-device-tdm-playback.m4"
grep -Fq '.stream_name = #did" MI2S Playback",' "$q6ports"
grep -Fq 'Q6AFE_TDM_PB_DAI("Tertiary", 0, TERTIARY_TDM_RX_0),' "$q6ports"
grep -Fq '"DEVICE_NAME MI2S Playback, , NAME_PREFIX.tdm_rx$1"' "$firmware/subgraph-device-tdm-playback.m4"
grep -Fq 'stream_name "$13 MI2S Playback"' "$firmware/module_tdm.m4"
grep -Fq 'SectionWidget."NAME_PREFIX.tdm_rx$1"' "$firmware/module_tdm.m4"
grep -Fq '"NAME_PREFIX.tdm_rx$1, , NAME_PREFIX.logger$1"' "$firmware/subgraph-device-tdm-playback.m4"
! grep -Fq 'TDM Playback' "$firmware/module_tdm.m4"
! grep -Fq 'TDM Playback' "$firmware/subgraph-device-tdm-playback.m4"
! grep -Fq 'LPASS_CLK_ID_INTF2_IBIT' "$dts"
! grep -Fq 'dai@38' "$dts"
! grep -Fq '0x504' "$dts"
test "$(grep -Fc 'dai-tdm-slot-num = <4>;' "$dts")" -eq 2
test "$(grep -Fc 'dai-tdm-slot-width = <32>;' "$dts")" -eq 2
test "$(grep -Fc 'dai-tdm-slot-rx-mask = <1 1>;' "$dts")" -eq 2

rg -q '^#define\s+AW88261_TDM_RATE\s+\(48000\)$' "$aw_h"
grep -Fq 'unsigned int tdm_sysclk;' "$aw_h"
grep -Fq 'unsigned int i2stxen_st;' "$aw_h"
! grep -Fq 'aw88261_dev_configure_tdm' "$aw_c"
printf '%s\n' "$codec_start" | rg -q -U 'aw88261_dev_pwd\(aw_dev, false\);[\s\S]*ret = aw88261_dev_check_syspll\(aw_dev\);'
printf '%s\n' "$codec_reg_update" | rg -q -U 'if \(reg_addr == AW88261_I2SCTRL3_REG\) \{\n\s*aw88261->i2stxen_st = reg_val & \(~AW88261_I2STXEN_MASK\);\n\s*reg_val &= AW88261_I2STXEN_MASK;\n\s*reg_val \|= AW88261_I2STXEN_DISABLE_VALUE;\n\s*\}'
printf '%s\n' "$codec_reg_update" | rg -q -U 'ret = regmap_write\(aw_dev->regmap, reg_addr, reg_val\);\n\s*if \(ret\)\n\s*break;\n\s*\}\n\s*\n\s*if \(ret\)\n\s*return ret;\n\s*\n\s*ret = aw88261_dev_set_vcalb\(aw_dev\);'
printf '%s\n' "$codec_tx_enable" | grep -Fq 'AW88261_I2SCTRL3_REG'
printf '%s\n' "$codec_tx_enable" | grep -Fq 'aw88261->i2stxen_st'
printf '%s\n' "$codec_tx_enable" | grep -Fq 'static int aw88261_dev_i2s_tx_enable'
printf '%s\n' "$codec_tx_enable" | grep -Fq 'return regmap_update_bits'
! printf '%s\n' "$codec_tx_enable" | grep -Fq 'AW88261_I2SCFG1_REG'
! grep -Fq 'AW88261_I2SCTRL2_REG' "$aw_c"
printf '%s\n' "$codec_start" | rg -q -U 'ret = aw88261_dev_i2s_tx_enable\(aw88261, true\);\n\s*if \(ret\)\n\s*goto sysst_check_fail;[\s\S]*aw88261_reg_force_set\(aw88261\);'

printf '%s\n' "$set_tdm_slot" | grep -Fq 'case 0:'
printf '%s\n' "$set_tdm_slot" | grep -Fq 'case 4:'
! printf '%s\n' "$set_tdm_slot" | grep -Fq 'case 8:'
printf '%s\n' "$set_tdm_slot" | grep -Fq 'if (tx_mask || rx_mask != GENMASK(1, 0) || slot_width != 32)'
printf '%s\n' "$set_tdm_slot" | grep -Fq 'aw88261->tdm_sysclk = AW88261_TDM_RATE * slots * slot_width;'
printf '%s\n' "$set_tdm_slot" | rg -q -U 'case 0:\n\s*aw88261->tdm_sysclk = 0;\n\s*return 0;'
printf '%s\n' "$set_sysclk" | grep -Fq 'freq != aw88261->tdm_sysclk'
! printf '%s\n' "$set_sysclk" | grep -Fq 'freq != 12288000'

for path in \
	sound/soc/qcom/qdsp6/audioreach.h \
	sound/soc/qcom/qdsp6/audioreach.c \
	sound/soc/qcom/qdsp6/topology.c \
	sound/soc/qcom/qdsp6/q6dsp-lpass-ports.c \
	sound/soc/qcom/sc8280xp.c \
	sound/soc/codecs/aw88261.c \
	sound/soc/codecs/aw88261.h \
	arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts; do
	tar -xOf "$kernel_archive" "./$path" | cmp -s "$kernel/$path" -
done

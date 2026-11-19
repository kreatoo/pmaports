#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
kernel="$root/../mondrian-linux"
firmware="$root/device/testing/firmware-xiaomi-mondrian"
dts="$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
aw_c="$kernel/sound/soc/codecs/aw88261.c"
aw_h="$kernel/sound/soc/codecs/aw88261.h"

speaker_switch=$(grep -A7 'speaker_switch_default: speaker-switch-default-state' "$dts")
printf '%s\n' "$speaker_switch" | grep -Fq 'bias-disable;'
printf '%s\n' "$speaker_switch" | grep -Fq 'output-low;'
! printf '%s\n' "$speaker_switch" | grep -Fq 'output-high;'

grep -q 'MODULE_ID_AUDIO_IF_SINK' "$kernel/sound/soc/qcom/qdsp6/audioreach.h"
grep -q 'PARAM_ID_AUDIO_IF_INTF_CFG' "$kernel/sound/soc/qcom/qdsp6/audioreach.h"
grep -q 'AR_TKN_U16_MODULE_INTF_MODE' "$kernel/include/uapi/sound/snd_ar_tokens.h"
grep -q 'audioreach_audio_if_set_media_format' "$kernel/sound/soc/qcom/qdsp6/audioreach.c"
grep -q 'struct apm_audio_if_module_intf_cfg' "$kernel/sound/soc/qcom/qdsp6/audioreach.c"
grep -q 'struct apm_module_hw_ep_frame_duration_cfg' "$kernel/sound/soc/qcom/qdsp6/audioreach.c"
grep -q 'APM_AUDIO_IF_INTF_CFG_PSIZE' "$kernel/sound/soc/qcom/qdsp6/audioreach.c"
grep -q 'APM_HW_EP_FRAME_DURATION_PSIZE' "$kernel/sound/soc/qcom/qdsp6/audioreach.c"
grep -q 'MODULE_ID_AUDIO_IF_SINK' "$kernel/sound/soc/qcom/qdsp6/topology.c"
grep -q 'static int q6tdm_set_tdm_slot' "$kernel/sound/soc/qcom/qdsp6/q6apm-lpass-dais.c"
grep -Fq '.set_tdm_slot	= q6tdm_set_tdm_slot,' "$kernel/sound/soc/qcom/qdsp6/q6apm-lpass-dais.c"
grep -Fq '.set_sysclk	= q6i2s_set_sysclk,' "$kernel/sound/soc/qcom/qdsp6/q6apm-lpass-dais.c"
grep -q 'LPASS_CLK_ID_INTF2_IBIT' "$kernel/include/dt-bindings/sound/qcom,q6dsp-lpass-ports.h"
grep -q 'sc8280xp_tdm_hw_params' "$kernel/sound/soc/qcom/sc8280xp.c"
grep -q 'snd_soc_tdm_params_to_bclk' "$kernel/sound/soc/qcom/sc8280xp.c"
grep -q 'qcom_snd_apply_dai_tdm_slots_cfg' "$kernel/sound/soc/qcom/sc8280xp.c"
grep -q 'dai-tdm-slot-num' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
! grep -q 'LPASS_CLK_ID_INTF2_IBIT' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
! grep -q 'qcom,prmcc_clk' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
! grep -q 'q6apm_set_sysclk' "$kernel/sound/soc/qcom/qdsp6/q6apm-lpass-dais.c"
grep -q 'ret = audioreach_set_media_format(graph, module, cfg);' "$kernel/sound/soc/qcom/qdsp6/q6apm.c"
grep -q 'if (ret)' "$kernel/sound/soc/qcom/qdsp6/q6apm.c"
awk '
	/- awinic,aw88261/ { aw88261 = 1; next }
	aw88261 && /reset-gpios: false/ { exit 1 }
	aw88261 && /- if:/ { exit 0 }
	END { exit 0 }
' "$kernel/Documentation/devicetree/bindings/sound/awinic,aw88395.yaml"
grep -q 'SND_SOC_DAIFMT_DSP_A' "$kernel/sound/soc/codecs/aw88261.c"
grep -q 'SND_SOC_DAIFMT_BC_FC' "$kernel/sound/soc/codecs/aw88261.c"
grep -q 'SNDRV_PCM_FORMAT_S16_LE' "$kernel/sound/soc/codecs/aw88261.c"
grep -q 'params_rate(params) != 48000' "$kernel/sound/soc/codecs/aw88261.c"
rg -q '^#define\s+AW88261_EFCTRL2_INIT_VALUE\s+\(0x1d40\)$' "$aw_h"
rg -q -U 'if \(chip_id != AW88261_CHIP_ID\) \{[\s\S]*dev_info\(&i2c->dev, "chip id = %x\\n", chip_id\);[\s\S]*ret = regmap_write\(regmap, AW88261_EFCTRL2_REG,[\s\S]*AW88261_EFCTRL2_INIT_VALUE\);[\s\S]*if \(ret\)[\s\S]*return dev_err_probe\(&i2c->dev, ret,[\s\S]*"failed to initialize EFCTRL2\\n"\);[\s\S]*usleep_range\(AW88261_3000_US, AW88261_3000_US \+ 10\);' "$aw_c"
rg -q -U 'gpiod_set_value_cansleep\(aw88261->reset_gpio, 1\);\n\s*usleep_range\(AW88261_3000_US, AW88261_3000_US \+ 10\);' "$aw_c"
test "$(rg -c 'AW88261_EFCTRL2_INIT_VALUE' "$aw_c")" -eq 1
grep -q 'firmware-xiaomi-mondrian-audio' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
awk '$0 == "\tfirmware-xiaomi-mondrian-audio" { getline; exit $0 != "\tfirmware-xiaomi-mondrian-tplg=1-r17" }' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
grep -q 'aw882xx_acf.bin' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -Fqx 'pkgrel=17' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -Fqx 'pkgrel=24' "$root/device/testing/linux-postmarketos-qcom-sm8450/APKBUILD"
grep -q 'CONFIG_SND_SOC_AW88261=y' "$root/device/testing/linux-postmarketos-qcom-sm8450/config-postmarketos-qcom-sm8450.aarch64"
grep -q 'awinic,aw88261' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'aw882xx_acf.bin' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'sound-name-prefix = "Top Speaker"' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'sound-name-prefix = "Bottom Speaker"' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'speaker-playback-dai-link' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'link-name = "Primary Speaker Playback"' "$kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-mondrian.dts"
grep -q 'Xiaomi-Mondrian.m4' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q 'subgraph-device-tdm-playback.m4' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q 'audioreach-audio-if-tokens.m4' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q '\$pkgname-tplg' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -q 'qcom/sm8450/Xiaomi-Mondrian-tplg.bin' "$root/device/testing/firmware-xiaomi-mondrian/APKBUILD"
grep -Fq "DEVICE_SG_ADD(subgraph-device-tdm-playback.m4, \`TERTIARY_TDM_RX_0', TERTIARY_TDM_RX_0," "$firmware/Xiaomi-Mondrian.m4"
grep -Fq "\`S16_LE', 48000, 48000, 2, 2," "$firmware/Xiaomi-Mondrian.m4"
grep -Fq 'LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_TERTIARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,' "$firmware/Xiaomi-Mondrian.m4"
grep -Fq "0x00004003, 0x00004003, 0x00006020, \`TERTIARY_TDM_RX_0')" "$firmware/Xiaomi-Mondrian.m4"
grep -q 'TERTIARY_TDM_RX_0' "$root/device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4"
grep -Fq 'AR_MODULE_LOG(MOD_INDEX, SG_INDEX, CONTAINER_INDEX' "$firmware/subgraph-device-tdm-playback.m4"
grep -q 'define(`AR_MODULE_TDM_RX' "$firmware/module_tdm.m4"
grep -Fq 'AR_TKN_U32_MODULE_ID STR(MODULE_ID_TDM_SINK)' "$firmware/module_tdm.m4"
grep -Fq 'AR_TKN_U32_MODULE_ACTIVE_LANE_MASK STR($19)' "$firmware/module_tdm.m4"
grep -Fq 'AR_MODULE_TDM_RX(MOD_INDEX, SG_INDEX, CONTAINER_INDEX' "$firmware/subgraph-device-tdm-playback.m4"
grep -Fq 'NONE_IID, 0x3, 4, 32, 0, 0x2, 48000' "$firmware/subgraph-device-tdm-playback.m4"
grep -q 'DEVICE_SG_ADD(subgraph-device-tdm-playback.m4' "$root/device/testing/firmware-xiaomi-mondrian/Xiaomi-Mondrian.m4"
grep -Fq "STREAM_DEVICE_PLAYBACK_ROUTE(TERTIARY_TDM_RX_0, \`\`TERTIARY_TDM_RX_0 Audio Mixer'', \`\`MultiMedia1, stream0.logger1'', \`\`MultiMedia2, stream1.logger1'')" "$firmware/Xiaomi-Mondrian.m4"
grep -Eq '^[[:space:]]*firmware-xiaomi-mondrian-tplg=1-r17$' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
grep -Fqx 'pkgrel=21' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
grep -Eq '^[[:space:]]*busybox-extras$' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
grep -Eq '^[[:space:]]*pmos-usb-telnet\.service$' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
grep -Eq '^[[:space:]]*install -Dm644 "\$srcdir/pmos-usb-telnet\.service" "\$pkgdir/usr/lib/systemd/system/pmos-usb-telnet\.service"$' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
grep -Eq '^[[:space:]]*ln -s /usr/lib/systemd/system/pmos-usb-telnet\.service "\$pkgdir/etc/systemd/system/multi-user\.target\.wants/pmos-usb-telnet\.service"$' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
test -f "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx '[Unit]' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx 'Description=Telnet recovery service for USB networking' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx 'After=network.target' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx '[Service]' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx 'ExecStart=/usr/sbin/telnetd -b 172.16.42.1:2222 -F -l /bin/login' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx 'Restart=on-failure' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx 'RestartSec=2' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx '[Install]' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
grep -Fqx 'WantedBy=multi-user.target' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
test "$(wc -l < "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service")" -eq 11
tail -n 1 "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service" | grep -Fqx 'WantedBy=multi-user.target'
checksum=$(sha512sum "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service")
checksum=${checksum%% *}
grep -Fqx "$checksum  pmos-usb-telnet.service" "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
! grep -Eq 'sshd|openssh-server' "$root/device/testing/device-xiaomi-mondrian/APKBUILD"
! grep -Eq 'ssh|sshd' "$root/device/testing/device-xiaomi-mondrian/pmos-usb-telnet.service"
! test -e "$root/device/testing/device-xiaomi-mondrian/pmos-usb-sshd.service"

for source in Xiaomi-Mondrian.m4 subgraph-device-tdm-playback.m4 audioreach-audio-if-tokens.m4; do
	checksum=$(sha512sum "$firmware/$source")
	checksum=${checksum%% *}
	test "$(grep -Fxc "$checksum  $source" "$firmware/APKBUILD")" -eq 1
	test "$(grep -Ec "[[:space:]]$source$" "$firmware/APKBUILD")" -eq 2
done

! grep -q 'MI2S Playback' "$firmware/subgraph-device-tdm-playback.m4"

archive="$root/device/testing/linux-postmarketos-qcom-sm8450/linux-local.tar.gz"
tar -xOf "$archive" ./sound/soc/qcom/qdsp6/audioreach.c | grep -q 'struct apm_audio_if_module_intf_cfg'
tar -xOf "$archive" ./sound/soc/qcom/qdsp6/audioreach.c | grep -q 'audioreach_audio_if_set_media_format'
tar -xOf "$archive" ./sound/soc/codecs/aw88261.c | cmp -s - "$aw_c"
tar -xOf "$archive" ./sound/soc/codecs/aw88261.h | cmp -s - "$aw_h"
! tar -tzf "$archive" | grep -q 'scripts/kconfig/conf\.o$'

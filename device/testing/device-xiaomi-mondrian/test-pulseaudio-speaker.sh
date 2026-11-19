#!/bin/sh
set -eu

base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
apkbuild="$base/APKBUILD"
card="$base/alsa-ucm-conf/mondrian.conf"
hifi="$base/alsa-ucm-conf/HiFi.conf"

test -f "$card"
test -f "$hifi"

grep -Fq 'pkgrel=21' "$apkbuild"
grep -Fq 'alsa-ucm-conf' "$apkbuild"
grep -Fq 'firmware-xiaomi-mondrian-tplg=1-r17' "$apkbuild"
grep -Fq 'alsa-ucm-conf/HiFi.conf' "$apkbuild"
grep -Fq 'alsa-ucm-conf/mondrian.conf' "$apkbuild"
grep -Fq '/usr/share/alsa/ucm2/Xiaomi/mondrian/' "$apkbuild"
grep -Fq '/usr/share/alsa/ucm2/conf.d/sm8450' "$apkbuild"
grep -Fq '../../Xiaomi/mondrian/mondrian.conf' "$apkbuild"

grep -Fq 'Syntax 3' "$card"
grep -Fq 'SectionUseCase."HiFi"' "$card"
grep -Fq 'File "/Xiaomi/mondrian/HiFi.conf"' "$card"

grep -Fq 'Syntax 3' "$hifi"
grep -Fq 'SectionVerb' "$hifi"
grep -Fq 'SectionDevice."Speaker"' "$hifi"
grep -Fq 'PlaybackPCM "hw:${CardId},0"' "$hifi"
grep -Fq 'PlaybackChannels 2' "$hifi"
grep -Fq "name='Top Speaker PCM Playback Volume' 600" "$hifi"
grep -Fq "name='Bottom Speaker PCM Playback Volume' 600" "$hifi"
grep -Fq "name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 1" "$hifi"
grep -Fq "name='Top Speaker PCM Playback Volume' 720" "$hifi"
grep -Fq "name='Bottom Speaker PCM Playback Volume' 720" "$hifi"
grep -Fq "name='TERTIARY_TDM_RX_0 Audio Mixer MultiMedia1' 0" "$hifi"

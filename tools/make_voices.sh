#!/bin/sh
# Renders the units' spoken lines to assets/audio/voice/*.wav with macOS's text-to-speech. There is no
# Latin voice, so an Italian one reads the Latin (which suits the church pronunciation well). Needs
# `say` and `ffmpeg`. Run from the project root; the results are committed, so this is only needed to
# change the lines.
set -e
OUT=assets/audio/voice
mkdir -p $OUT
TMP=$(mktemp -d)
render() {  # name voice rate text
	say -v "$2" -r "$3" -o "$TMP/$1.aiff" "$4"
	ffmpeg -y -loglevel error -i "$TMP/$1.aiff" -af "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=1:stop_threshold=-45dB:stop_duration=0.15,loudnorm=I=-18:TP=-2,apad=pad_dur=0.05" -ar 22050 -ac 1 -c:a pcm_s16le "$OUT/$1.wav"
}
# Citizens: "What do you wish?"
render villager_m_0 Reed 150 "Quid vis?"
render villager_m_1 Reed 150 "Quid desideras?"
render villager_m_2 Reed 150 "Ecce, domine."
render villager_f_0 Alice 150 "Quid vis?"
render villager_f_1 Alice 150 "Quid desideras?"
render villager_f_2 Alice 150 "Ecce, domina."
# Soldiers: "Ready."
render soldier_0 Reed 160 "Paratus."
render soldier_1 Reed 160 "Adsum."
render soldier_2 Reed 160 "Iube, imperator."
rm -rf "$TMP"

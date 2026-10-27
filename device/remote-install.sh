#!/bin/sh
# The device half of install.sh, run as root from the temporary directory lib/remote.sh made (and removes).
# Not meant to be run by hand.   remote-install.sh DIR
# DIR/payload: mu300-audio.tar.gz and SHA256SUMS (checked again here), agdsp.bin (own-firmware: the user's own
# image), headset.
set -eu
P=$1/payload
export PATH="$PATH:/opt/mu300/bin:/opt/mu300/busybox-bin:/usr/sbin:/sbin"
umask 022
DISK=/mnt/mu300-disk
command -v mu300-extra >/dev/null 2>&1 || { echo "this mu300-linux has no mu300-extra: update it first (mu300-update apply)" >&2; exit 1; }
(cd "$P" && sha256sum -c SHA256SUMS >/dev/null) || { echo "mu300-audio.tar.gz does not match SHA256SUMS" >&2; exit 1; }
# the audio extra of mu300-audio up to v1.0.5 goes first: the two would link the same files
if [ -d "$DISK/extra/audio" ]; then mu300-extra remove audio || exit 1; fi
# the pinned image goes where hooks/link takes it from for every system; one of your own into this system only
if [ -f "$P/agdsp.bin" ] && [ ! -f "$P/own-firmware" ]; then
    mkdir -p "$DISK/extra/.mu300-audio-firmware"
    cp "$P/agdsp.bin" "$DISK/extra/.mu300-audio-firmware/agdsp.bin"
fi
mu300-extra install mu300-audio --from "$P"
if [ -f "$P/own-firmware" ]; then /opt/mu300/bin/mu300-audio-dsp install "$P/agdsp.bin"; fi
if [ -f "$P/headset" ]; then
    h=$(cat "$P/headset")
    case $h in [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]) ;;
        *) echo "the headset address is not AA:BB:CC:DD:EE:FF; not set" >&2; exit 1 ;; esac
    [ -f /etc/mu300/voice.conf ] || cp /etc/mu300/voice.conf.example /etc/mu300/voice.conf
    if grep -q '^BT_HEADSET=' /etc/mu300/voice.conf; then sed -i "s/^BT_HEADSET=.*/BT_HEADSET=$h/" /etc/mu300/voice.conf
    else echo "BT_HEADSET=$h" >> /etc/mu300/voice.conf; fi
    echo "headset: $h (/etc/mu300/voice.conf)"
fi
echo
echo "installed. Check:  mu300-audio-dsp status   (dsp: running - it answered)"

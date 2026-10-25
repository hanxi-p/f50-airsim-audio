# mu300-audio

Call audio for the ZTE F50 (MU300) and ZTE U30 Air running [mu300-linux](https://github.com/dikeckaan/mu300-linux),
installed on the device as its **audio extra**.

Supported kernels: the vendor 5.4 and the mainline 6.18, 7.2 and 7.3 that mu300-linux ships.

## Install

On the device (Ubuntu or OpenWrt, a mu300-linux release after v2026.10.19.1):

    sudo mu300-extra install audio                   # the kernel this device uses
    sudo mu300-extra install audio --from DIR        # offline: the release's tarball, SHA256SUMS and agdsp.bin
    mu300-extra status audio
    sudo mu300-extra remove audio

`mu300-update` keeps it in step with the kernel. From a computer: `./install.sh --host root@192.168.77.1`
(`./uninstall.sh` to remove).

## Bluetooth headset

Pair and trust the headset with `bluetoothctl`, put its address in `/etc/mu300/voice.conf` (`BT_HEADSET=...`; see
`/etc/mu300/voice.conf.example`) and restart the `mu300-voice` service.

Reports go to the [mu300-linux issues](https://github.com/dikeckaan/mu300-linux/issues).

## Building

    sh kernel/build.sh 6.18                                   # out/modules/6.18/
    for t in pcmhost ctlset hfp; do sh src/$t/build.sh; done  # out/bin/
    sh tools/make-extra.sh out/release v1.0.0                 # the release files
    cd tests && python3 -m unittest discover -s .

## Credits

* **kano (kanoqwq)** and [e5-linux](https://github.com/kanoqwq/e5-linux) (MIT, © 2026 Enceka): parts of this work
  are ported from there; each ported piece names its e5-linux commit.
* **Enceka**: [linux-lts-e5](https://github.com/Enceka/linux-lts-e5), which the mainline port drew on.
* Unisoc wrote the audio drivers (GPL-2.0).

## Licence

Two licences, see [LICENSE](LICENSE): **GPL-2.0** ([kernel/COPYING](kernel/COPYING)) for the drivers - their sources,
patches and builds - and the build kits; **MIT** for the scripts, tools and tests. No firmware or vendor parameter
file is in this repository or its releases, and none may be added.

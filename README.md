# HammerOS 0.1 — "Forge" 
# WORK IN PROGRESS"

An ultra-light, **built-from-source** Linuxdistribution:
upstream **Linux kernel** + **musl libc** + **BusyBox** userland. No Debian,
no Ubuntu, no distro base packages — every binary in the ISO comes from
pinned upstream source tarballs compiled by `build.sh`.

```
anvil
  └── hammer    <- this OS
```

## Design targets

| Target | Value |
|---|---|
| Live RAM footprint (idle GUI) | ≤ 1.5 GB |
| ISO size (0.1 core) | < 150 MB |
| Boot | BIOS first, UEFI on 0.2 |
| Persistence | savefile overlay (0.2) |
| GUI | X11 fbdev server + JWM (0.2) |

## Build it

You need a Linux host with `gcc`, `make`, `cpio`, and `xorriso` +
`syslinux-common isolinux` (for ISO mastering — `apt install xorriso
syslinux-common isolinux` on Debian-family hosts):

```bash
./build.sh fetch     # download + verify upstream sources into work/src
./build.sh kernel    # compile the lean upstream kernel
./build.sh rootfs    # musl + busybox (+dropbear) static, assemble rootfs
./build.sh iso       # pack the hybrid ISO
./build.sh           # everything in order
```

Artifact: `hammeros-0.1.0-amd64.iso` + `.sha256`.

## Roadmap

- 0.1 — boot/live: kernel, custom init, DHCP net, dropbear ssh
- 0.2 — GUI: X (fbdev/kdrive from source) + JWM + st; savefile persistence
- 0.3 — apps + hammer-pkg (musl-compatible static packages, update channel)

## Repo layout

```
build.sh            # all stages: fetch / kernel / rootfs / iso
configs/            # kernel.config, busybox.config (hand-trimmed)
rootfs/             # overlay: /init, /etc/inittab, /etc/rc.init, banner
boot/isolinux.cfg   # bootloader menu
work/               # gitignored build dir (sources, objfs)
```

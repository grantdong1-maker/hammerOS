# hammerOS — "Forge"

> **status: 0.3 is live** — 1.3 GB feature-packed ISO, X11 + JWM desktop,
> boot-tested. 0.2's 11 MB framebuffer desktop is still the failsafe.

An ultra-light, **built-from-source** Linux core with a fat feature layer on
top: upstream **Linux kernel** + **musl libc** + **BusyBox** + **dropbear** +
**links**, all compiled from pinned upstream tarballs by `build.sh` — plus a
Debian **bookworm** package set (older stable) delivered as a squashfs,
Puppy-Woof style.

```
anvil
  ├── hammer    <- AnvilOS 1.0 (the big distro, Debian live-build)
  └── forge     <- this OS (from-source core + Debian feature layer)
```

## Design targets

| Target | Value |
|---|---|
| ISO size | ~1.5 GB (feature-packed) — currently **1.3 GB** |
| Live RAM footprint (idle X) | ~1 GB |
| Core | upstream kernel + musl + BusyBox — **compiled from source** |
| Feature layer | Debian **bookworm** packages, squashfs (xz+BCJ), Puppy-style |
| Boot | BIOS (isolinux) — UEFI on 0.4 |
| Persistence | savefile overlay (0.4) |
| GUI | X11 + JWM · framebuffer `hammerwm` failsafe kept |

## How it boots

1. isolinux loads the source-built kernel + BusyBox initramfs.
2. `/init` scans CD/USB for `live/live.squashfs` (retries while slow media
   probes), mounts it read-only, stacks a tmpfs **overlayfs** on top, and
   `run-init`s into it — so the whole system runs in RAM and the media can be
   pulled after boot.
3. Debian layer takes over: systemd → slim (autologin `root`) → `.xinitrc` →
   PipeWire + dbus + **JWM** in the grey/ember theme.
4. No layer found → falls back to the 11 MB framebuffer desktop (`hammerwm`).

## What's in the 1.3 GB

Browsers/mail: Firefox ESR, Thunderbird · Office: LibreOffice Writer/Calc/Impress
· Graphics: GIMP, Inkscape, Blender, ImageMagick · Media: VLC, mpv, ffmpeg,
Audacity, OBS Studio · Games: ScummVM, Frozen Bubble, Extreme Tux Racer ·
System: GParted, Transmission, testdisk, rclone, 7zip, ncdu, mc, htop ·
Dev: build-essential, Python 3 + numpy, git, vim · Network: NetworkManager,
wpasupplicant, openssh-client · Firmware: Intel/AMD/Realtek/Atheros/Broadcom
WiFi + GPU, plus all Xorg video drivers (Intel, AMD, NVIDIA/nouveau, VMware,
VirtualBox, QXL, virtio).

Deliberately cut to hit the size target: 32-bit Wine multiarch (i386),
SuperTuxKart/SuperTux data (≈940 MB), non-English locales, HTML docs.

## Build it

Host needs `gcc`, `make`, `cpio`, `flex`, `bison`, `libelf-dev`, `libssl-dev`,
`bc`, `xorriso`, `syslinux-common`/`isolinux`, and `debootstrap` +
`squashfs-tools` for the layer (`sudo` for that stage):

```bash
./build.sh fetch     # download + verify upstream sources into work/src
./build.sh kernel    # compile the kernel (configs/kernel.config)
./build.sh layer     # debootstrap bookworm + curated pkgs -> live.squashfs (sudo)
./build.sh rootfs    # musl + busybox + dropbear + links, static; assemble initramfs
./build.sh iso       # pack the hybrid ISO
./build.sh           # everything in order
```

Artifact: `hammeros-<version>-amd64.iso` + `.sha256`.

## Roadmap

- 0.1 — boot/live: kernel, custom init, DHCP net, dropbear ssh ✅
- 0.2 — GUI: framebuffer desktop (`hammerwm`) + **links** graphical browser ✅
- 0.3 — X11 + JWM desktop with the Debian bookworm feature layer, GPU/sound/
  WiFi drivers, live squashfs + overlayfs boot ✅
- 0.4 — savefile persistence, UEFI boot, `hammeros-install` to USB/disk
- 0.5 — forge-pkg (musl-compatible static packages for the core, update channel)

## Repo layout

```
build.sh              # stages: fetch / kernel / layer / rootfs / iso
configs/              # kernel.config, busybox.config (hand-trimmed)
scripts/              # mk-debian-layer.sh, jwmrc (validated with `jwm -p`)
rootfs/               # initramfs overlay: /init, /etc/inittab, rc.init, hammerwm
boot/isolinux.cfg     # bootloader menu
work/                 # gitignored build dir (sources, layer, objfs)
```

## Releases

- [0.2.0](https://github.com/grantdong1-maker/hammerOS/releases/tag/0.2.0) —
  11 MB source-only framebuffer desktop.

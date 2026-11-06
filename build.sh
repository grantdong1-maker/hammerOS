#!/usr/bin/env bash
# hammerOS ("Forge") build system — builds an ultra-light Linux from
# upstream sources only: linux kernel + musl + busybox + dropbear.
#
#   ./build.sh [fetch|kernel|rootfs|iso|all]
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

W="$SCRIPT_DIR/work"
SRC="$W/src"
OUT="$W/out"
ROOT="$W/rootfs.staging"
TC="$W/toolchain"

VER_BUSY="1.36.1"
VER_MUSL="1.2.5"
VER_DROP="2024.86"
VER_KERN="${VER_KERN:-auto}"     # auto = detect newest 6.12 LTS patch
ISOVER="0.1.0"
JOBS="$(nproc)"

fetch() {
    local url="$1" file="$2"
    [ -f "$SRC/$file" ] && { echo "have: $file"; return 0; }
    mkdir -p "$SRC"
    echo "fetch: $file"
    curl -fL --retry 3 -o "$SRC/$file.tmp" "$url" && mv "$SRC/$file.tmp" "$SRC/$file"
}

latest_612() {
    [ "$VER_KERN" != auto ] && { echo "$VER_KERN"; return; }
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v6.x/" |
        grep -oE 'linux-6\.12\.[0-9]+\.tar\.xz' | sort -t. -k3 -n | tail -1 |
        sed 's/linux-6\.12\.//;s/\.tar\.xz//'
}

stage_fetch() {
    mkdir -p "$SRC" "$OUT" "$ROOT" "$W"
    KVER="$(latest_612)"; echo "kernel: linux-6.12.$KVER"
    fetch "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.${KVER}.tar.xz" "linux-6.12.${KVER}.tar.xz"
    fetch "https://busybox.net/downloads/busybox-${VER_BUSY}.tar.bz2" "busybox-${VER_BUSY}.tar.bz2"
    fetch "https://musl.libc.org/releases/musl-${VER_MUSL}.tar.gz" "musl-${VER_MUSL}.tar.gz"
    fetch "https://matt.ucc.asn.au/dropbear/releases/dropbear-${VER_DROP}.tar.bz2" "dropbear-${VER_DROP}.tar.bz2"
    echo "fetch done"
}

stage_kernel() {
    stage_fetch
    local ksrc="$SRC/linux-6.12.${KVER}"
    if [ -f "$OUT/bzImage" ]; then echo "kernel: already built"; return 0; fi
    [ -d "$ksrc" ] || tar -xf "$SRC/linux-6.12.${KVER}.tar.xz" -C "$SRC"
    (
        cd "$ksrc"
        cp "$SCRIPT_DIR/configs/kernel.config" .config
        make -j"$JOBS" olddefconfig
        make -j"$JOBS" bzImage
    )
    cp "$ksrc/arch/x86/boot/bzImage" "$OUT/bzImage"
    echo "kernel done: work/out/bzImage"
}

stage_rootfs() {
    stage_fetch
    export PATH="$TC/bin:$PATH"

    # ---- musl (provides musl-gcc wrapper for static userland builds) ------
    [ -d "$SRC/musl-${VER_MUSL}" ] || tar -xf "$SRC/musl-${VER_MUSL}.tar.gz" -C "$SRC"
    if [ ! -x "$TC/bin/musl-gcc" ]; then
        mkdir -p "$SRC/build-musl"
        (cd "$SRC/build-musl" && "$SRC/musl-${VER_MUSL}"/configure \
            --prefix="$TC" --disable-gcc-wrapper \
            && make -j"$JOBS" && make install
         # wrapper is generated in-tree even with --disable-gcc-wrapper? ensure:
         )
        # generate the musl-gcc wrapper script
        (cd "$SRC/musl-${VER_MUSL}" && ./configure --prefix="$TC" >/dev/null 2>&1 \
            && make -s obj/musl-gcc >/dev/null 2>&1) || true
        mkdir -p "$TC/bin" "$TC/lib" "$TC/include"
        install -m 755 "$SRC/musl-${VER_MUSL}/obj/musl-gcc" "$TC/bin/" 2>/dev/null \
            || { echo "musl-gcc wrapper missing"; exit 1; }
        cp -a "$SRC/build-musl/lib"/* "$TC/lib/" 2>/dev/null || true
        cp -a "$SRC/musl-${VER_MUSL}/include"/* "$TC/include/" 2>/dev/null || true
        cp -a "$SRC/build-musl/obj/include"/* "$TC/include/" 2>/dev/null || true
        mkdir -p "$TC/lib/musl-gcc"
        cp -a "$SRC/build-musl/obj/rcrt1.o" "$SRC/build-musl/obj/crt1.o" \
            "$SRC/build-musl/obj/crti.o" "$SRC/build-musl/obj/crtn.o" "$TC/lib/musl-gcc/" 2>/dev/null || true
        cp -a "$SRC/build-musl/obj/libc.a" "$SRC/build-musl/obj/libc.so" "$TC/lib/musl-gcc/" 2>/dev/null || true
    fi
    MUSL_CC="$TC/bin/musl-gcc"
    export CC="$MUSL_CC"

    # ---- busybox (static) ------------------------------------------------
    local bsrc="$SRC/busybox-${VER_BUSY}"
    [ -d "$bsrc" ] || tar -xf "$SRC/busybox-${VER_BUSY}.tar.bz2" -C "$SRC"
    (
        cd "$bsrc"
        make defconfig
        sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' .config
        make -j"$JOBS" oldconfig </dev/null
        make -j"$JOBS"
    )
    # ---- dropbear (static ssh) -------------------------------------------
    local dsrc="$SRC/dropbear-${VER_DROP}"
    [ -d "$dsrc" ] || tar -xf "$SRC/dropbear-${VER_DROP}.tar.bz2" -C "$SRC"
    if [ ! -f "$dsrc/dropbear" ]; then
        (cd "$dsrc" &&
            CC="$MUSL_CC" ./configure --disable-zlib --disable-syslog &&
            make -j"$JOBS" PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp")
    fi

    # ---- assemble rootfs tree --------------------------------------------
    rm -rf "$ROOT"
    mkdir -p "$ROOT"/{bin,sbin,etc,dev,proc,sys,run,tmp,var/log,tmpfs,root,mnt,media,etc/dropbear,usr/share/udhcpc}
    BB="$bsrc/busybox"
    install -m 755 "$BB" "$ROOT/bin/busybox"
    ( cd "$ROOT/bin" && "$BB" --list | while read -r x; do
        [ "$x" = "busybox" ] || ln -sf busybox "$x"; done )
    for d in dropbear dbclient dropbearkey dropbearconvert scp; do
        install -m 755 "$dsrc/$d" "$ROOT/bin/"
    done
    ln -sf /bin/busybox "$ROOT/sbin/init"
    touch "$ROOT/etc/resolv.conf"
    cp -a rootfs/. "$ROOT/"
    chmod 755 "$ROOT/init" "$ROOT/etc/rc.init" "$ROOT/etc/rc.shutdown" \
              "$ROOT/usr/share/udhcpc/default.script"
    echo "rootfs assembled"
}

stage_iso() {
    stage_rootfs
    # ---- 1) initramfs cpio.gz ------------------------------------------
    ( cd "$ROOT" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 ) > "$OUT/initramfs.cpio.gz"
    # ---- 2) hybrid ISO (isolinux/BIOS) ----------------------------------
    local XB
    for c in /usr/lib/ISOLINUX /usr/share/syslinux /usr/lib/syslinux/bios; do
        [ -f "$c/isolinux.bin" ] && XB="$c" && break
    done
    [ -n "${XB:-}" ] || { echo "ERROR: install syslinux isolinux first:"; \
        echo "  sudo apt install xorriso syslinux-common isolinux"; exit 1; }
    local IT="$W/isotree"
    rm -rf "$IT"; mkdir -p "$IT/boot/isolinux"
    cp "$OUT/bzImage" "$IT/boot/"
    cp "$OUT/initramfs.cpio.gz" "$IT/boot/"
    cp "$XB/isolinux.bin" "$IT/boot/isolinux/"
    [ -f "$XB/ldlinux.c32" ] && cp "$XB/ldlinux.c32" "$IT/boot/isolinux/"
    sed "s|@VERSION@|${ISOVER}|" boot/isolinux.cfg > "$IT/boot/isolinux/isolinux.cfg"
    local ISO="$SCRIPT_DIR/hammeros-${ISOVER}-amd64.iso"
    xorriso -as mkisofs -o "$ISO" \
        -b boot/isolinux/isolinux.bin -c boot/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -J -R -V "hammerOS ${ISOVER} Forge" "$IT"
    sha256sum "$ISO" "$OUT/initramfs.cpio.gz" > "$ISO.sha256"
    ls -lh "$ISO" "$ISO.sha256"
    echo "hammerOS 0.1.0 built."
}

case "${1:-all}" in
    fetch)  stage_fetch ;;
    kernel) stage_kernel ;;
    rootfs) stage_rootfs ;;
    iso)    stage_iso ;;
    all)    stage_fetch; stage_kernel; stage_rootfs; stage_iso ;;
    *) echo "usage: $0 [fetch|kernel|rootfs|iso|all]"; exit 1 ;;
esac

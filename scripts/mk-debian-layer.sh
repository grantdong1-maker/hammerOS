#!/usr/bin/env bash
# hammerOS 0.3 feature layer: debootstrap an older Debian (bookworm) with a
# curated desktop package set, then squash it into work/out/live.squashfs.
# Run as root (the build.sh 'layer' stage does that for you).
set -euo pipefail
cd "$(dirname "$0")/.."

RELEASE=bookworm
MIRROR=http://deb.debian.org/debian
DIR="$PWD/work/layer/root"
OUT="$PWD/work/out/live.squashfs"
mkdir -p "$PWD/work/layer" "$PWD/work/out"

PKGS="
xorg xserver-xorg xserver-xorg-video-all xserver-xorg-input-all
x11-utils xterm slim jwm pcmanfm mousepad lxtask galculator
firefox-esr thunderbird
libreoffice gimp inkscape
vlc mpv ffmpeg imagemagick audacity
network-manager wpasupplicant
pipewire-audio wireplumber alsa-utils
build-essential python3 python3-pip git curl wget vim nano
htop mc ncdu tree jq zip unzip file dialog openssh-client
fonts-liberation fonts-dejavu fonts-noto-core fonts-ubuntu xfonts-base
firmware-iwlwifi firmware-amd-graphics firmware-misc-nonfree
firmware-realtek firmware-atheros firmware-brcm80211
"

if [ ! -d "$DIR/bin" ]; then
    echo "== debootstrap $RELEASE -> $DIR"
    debootstrap --variant=minbase --components=main,contrib,non-free,non-free-firmware \
        "$RELEASE" "$DIR" "$MIRROR"
fi

echo "== package install"
cat > "$DIR/etc/apt/apt.conf.d/99hammeros" <<'EOF'
APT::Install-Recommends "false";
APT::AutoRemove::RecommendsImportant "false";
EOF
# headless chroot: no debconf dialogs
cat > "$DIR/etc/apt/apt.conf.d/71noninteractive" <<'EOF'
apt::configure-options {"DEBIAN_FRONTEND"="noninteractive"; "APT::Color"="0";};
EOF
echo 'keyboard-configuration keyboard-configuration/layout select English (US)' | \
    tee "$DIR/tmp/preseed" >/dev/null
chroot "$DIR" env DEBIAN_FRONTEND=noninteractive debconf-set-selections /tmp/preseed
rm -f "$DIR/tmp/preseed"
chroot "$DIR" env DEBIAN_FRONTEND=noninteractive dpkg --configure -a
chroot "$DIR" env DEBIAN_FRONTEND=noninteractive apt-get update
chroot "$DIR" env DEBIAN_FRONTEND=noninteractive apt-get install -y $PKGS

echo "== hammerOS overlay config"
echo hammeros > "$DIR/etc/hostname"
printf '127.0.1.1\thammeros\n' > "$DIR/etc/hosts"
printf 'hammerOS 0.3 "Forge" — kernel+busybox from source, feature layer from Debian %s\n' "$RELEASE" \
    > "$DIR/etc/issue"

# slim: autologin root straight into the session
sed -i 's/^# default_user\s*default_user default_user/'"$USER"'/; s/^# auto_login no/auto_login yes/' \
    "$DIR/etc/slim.conf" 2>/dev/null || true
grep -q "^default_user root" "$DIR/etc/slim.conf" || \
    printf '\ndefault_user root\nauto_login yes\n' >> "$DIR/etc/slim.conf"

mkdir -p "$DIR/root/.jwm"
cat > "$DIR/root/.xinitrc" <<'EOF'
#!/bin/sh
xsetroot -solid '#26292e'
pipewire &
pipewire-pulse &
wireplumber &
exec dbus-launch --exit-with-session jwm
EOF
chmod 755 "$DIR/root/.xinitrc"

cat > "$DIR/root/.jwm/jwmrc" <<'EOF'
<JWM>
  <Tray height="28" valign="bottom">
    <Label width="10">hammerOS</Label>
    <Button action="menu"> Programs </Button>
    <Spacer/>
    <Clock format="%H:%M"/>
  </Tray>
  <Menu name="Programs" title="Programs">
    <Program label="Firefox" icon="firefox-esr">firefox-esr</Program>
    <Program label="Thunderbird">thunderbird</Program>
    <Separator/>
    <Program label="LibreOffice Writer">libreoffice --writer</Program>
    <Program label="LibreOffice Calc">libreoffice --calc</Program>
    <Program label="GIMP">gimp</Program>
    <Program label="Inkscape">inkscape</Program>
    <Program label="Blender">blender</Program>
    <Separator/>
    <Program label="VLC">vlc</Program>
    <Program label="Files">pcmanfm</Program>
    <Program label="Terminal">xterm</Program>
  </Menu>
  <Menu name="System" title="System">
    <Program label="Top">xterm -e htop</Program>
    <Restart/>
    <Exit/>
  </Menu>
  <TrayX>
    <Button action="rootmenu"> hammer </Button>
    <Spacer/>
    <Pager/>
  </TrayX>
  <Group>
    <Option>maximized</Option>
  </Group>
  <MoveMode>border</MoveMode>
  <OpaqueMove>1</OpaqueMove>
  <ResizeMode>outline</ResizeMode>
  <Theme>
    <Font name="sans" size="11"/>
    <Background color="#26292e"/>
    <TrayColor color="#1d2023"/>
    <MenuColor color="#26292e"/>
    <MenuTitleColor color="#ff8f40"/>
    <MenuActiveColor color="#33373b"/>
    <MenuActiveTextColor color="#ff8f40"/>
    <ButtonColor color="#26292e"/>
    <Text color="#e6e6e6"/>
    <TitleText color="#ff8f40"/>
  </Theme>
</JWM>
EOF
# blender is a nice-to-have; add if apt had it (bookworm main does)
chroot "$DIR" env DEBIAN_FRONTEND=noninteractive apt-get install -y blender 2>/dev/null || true

echo "== squash"
rm -f "$OUT.tmp"
chroot "$DIR" apt-get clean
mksquashfs "$DIR" "$OUT.tmp" -comp xz -noappend -b 1024k -Xbcj x86
mv "$OUT.tmp" "$OUT"
ls -lh "$OUT"
echo "LAYER_DONE"

#!/usr/bin/env bash

set -Eeuo pipefail

REPO_DIR="${1:?builder repository path is required}"
WORK_ROOT="${CT3003_WORK_ROOT:-$HOME/ct3003-emmc-build}"
SOURCE_DIR="$WORK_ROOT/openwrt"
CACHE_ROOT="$HOME/.cache/ct3003-emmc-openwrt"
DL_CACHE="$CACHE_ROOT/dl"
CCACHE_CACHE="$CACHE_ROOT/ccache"
OUTPUT_ROOT="$REPO_DIR/outputs/orbstack"
PID_FILE="$WORK_ROOT/build.pid"
JOBS="${CT3003_JOBS:-}"

if [[ -z "$JOBS" ]]; then
  cpu_count="$(nproc)"
  if (( cpu_count > 12 )); then
    JOBS=12
  else
    JOBS="$cpu_count"
  fi
fi

mkdir -p "$WORK_ROOT" "$CACHE_ROOT" "$DL_CACHE" "$CCACHE_CACHE" "$OUTPUT_ROOT"
exec 9>"$WORK_ROOT/build.lock"
if ! flock -n 9; then
  echo "Another CT3003 build already holds $WORK_ROOT/build.lock" >&2
  exit 1
fi
trap 'rm -f "$PID_FILE"' EXIT

log_section() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

run_parallel_with_serial_retry() {
  local target="$1"
  if ! nice -n 5 make "$target" -j"$JOBS"; then
    echo "Parallel build of $target failed; retrying with -j1 V=s." >&2
    nice -n 5 make "$target" -j1 V=s
  fi
}

log_section "Install Ubuntu build dependencies"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  ccache gettext git libelf-dev libncurses5-dev libssl-dev llvm \
  python3 python3-setuptools rsync swig unzip zlib1g-dev file wget

log_section "Seed persistent download cache"
if [[ ! -f "$CACHE_ROOT/.downloads-seeded" && -d "$HOME/openwrt/dl" ]]; then
  cp -al "$HOME/openwrt/dl/." "$DL_CACHE/" 2>/dev/null || \
    rsync -a --ignore-existing "$HOME/openwrt/dl/" "$DL_CACHE/"
  touch "$CACHE_ROOT/.downloads-seeded"
fi

log_section "Synchronize ImmortalWrt source"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone --depth 1 --branch master \
    https://github.com/airjinkela/immortalwrt-main.git "$SOURCE_DIR"
else
  # This tracked DTS is intentionally replaced below by the builder copy.
  # Restore only that generated change before advancing the persistent tree.
  git -C "$SOURCE_DIR" restore \
    target/linux/mediatek/dts/mt7981b-cetron-ct3003-emmc.dts
  if ! git -C "$SOURCE_DIR" diff --quiet || \
     ! git -C "$SOURCE_DIR" diff --cached --quiet; then
    echo "Tracked changes exist in $SOURCE_DIR; refusing to overwrite them." >&2
    git -C "$SOURCE_DIR" status --short >&2
    exit 1
  fi
  git -C "$SOURCE_DIR" switch master
  git -C "$SOURCE_DIR" pull --ff-only origin master
fi

if [[ -e "$SOURCE_DIR/dl" && ! -L "$SOURCE_DIR/dl" ]]; then
  rsync -a --ignore-existing "$SOURCE_DIR/dl/" "$DL_CACHE/"
  find "$SOURCE_DIR/dl" -mindepth 1 -delete
  rmdir "$SOURCE_DIR/dl"
fi
if [[ ! -L "$SOURCE_DIR/dl" ]]; then
  ln -s "$DL_CACHE" "$SOURCE_DIR/dl"
fi

if [[ -e "$SOURCE_DIR/.ccache" && ! -L "$SOURCE_DIR/.ccache" ]]; then
  rsync -a --ignore-existing "$SOURCE_DIR/.ccache/" "$CCACHE_CACHE/"
  find "$SOURCE_DIR/.ccache" -mindepth 1 -delete
  rmdir "$SOURCE_DIR/.ccache"
fi
if [[ ! -L "$SOURCE_DIR/.ccache" ]]; then
  ln -s "$CCACHE_CACHE" "$SOURCE_DIR/.ccache"
fi
ccache --max-size 20G

log_section "Synchronize OpenClash and pinned PassWall2 sources"
if [[ -d "$SOURCE_DIR/package/openclash/.git" ]]; then
  git -C "$SOURCE_DIR/package/openclash" pull --ff-only
else
  git clone --depth 1 https://github.com/vernesong/OpenClash.git \
    "$SOURCE_DIR/package/openclash"
fi

sync_pinned_repo() {
  local url="$1"
  local directory="$2"
  local commit="$3"
  if [[ ! -d "$directory/.git" ]]; then
    mkdir -p "$directory"
    git -C "$directory" init
    git -C "$directory" remote add origin "$url"
  fi
  git -C "$directory" fetch --depth 1 origin "$commit"
  git -C "$directory" switch --detach FETCH_HEAD
}

sync_pinned_repo \
  https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git \
  "$SOURCE_DIR/package/passwall-packages" \
  1f765fd55ff40d49221df91990ebe3ef9a669a63
wget -qO "$SOURCE_DIR/package/passwall-packages/v2ray-geodata/Makefile" \
  https://raw.githubusercontent.com/Openwrt-Passwall/openwrt-passwall-packages/eda14788fdeb07c6804d8bcf44d3eeec150930c1/v2ray-geodata/Makefile
sync_pinned_repo \
  https://github.com/Openwrt-Passwall/openwrt-passwall2.git \
  "$SOURCE_DIR/package/passwall2" \
  c8ed851e7a9f116c8743a6cfa95e25804237d3ec

cp "$REPO_DIR/dts/mt7981b-cetron-ct3003-emmc.dts" \
  "$SOURCE_DIR/target/linux/mediatek/dts/"
cp -a "$REPO_DIR/files/." "$SOURCE_DIR/files/"

log_section "Embed the pinned OpenClash Mihomo core"
CORE_VERSION=1.19.28
CORE_ARCHIVE="$DL_CACHE/mihomo-linux-arm64-v${CORE_VERSION}.gz"
CORE_SHA256=2474450cd1c41dfa53036a54a4e85579f493d3af524d86c3d4b8e2b240b56cd2
if [[ ! -f "$CORE_ARCHIVE" ]] || \
   ! echo "$CORE_SHA256  $CORE_ARCHIVE" | sha256sum -c -; then
  wget -O "$CORE_ARCHIVE" \
    "https://github.com/MetaCubeX/mihomo/releases/download/v${CORE_VERSION}/mihomo-linux-arm64-v${CORE_VERSION}.gz"
  echo "$CORE_SHA256  $CORE_ARCHIVE" | sha256sum -c -
fi
mkdir -p "$SOURCE_DIR/files/etc/openclash/core"
gzip -dc "$CORE_ARCHIVE" > "$SOURCE_DIR/files/etc/openclash/core/clash_meta"
chmod 0755 "$SOURCE_DIR/files/etc/openclash/core/clash_meta"
file "$SOURCE_DIR/files/etc/openclash/core/clash_meta" | grep -q 'ARM aarch64'

cd "$SOURCE_DIR"

log_section "Update feeds and validate the CT3003 configuration"
./scripts/feeds update -a
./scripts/feeds install -a
cp "$REPO_DIR/config/ct3003-emmc.config" .config
make defconfig
grep -q '^CONFIG_TARGET_mediatek_filogic_DEVICE_cetron_ct3003-emmc=y$' .config
grep -q '^CONFIG_CCACHE=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-openclash=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-passwall2=y$' .config
grep -q '^CONFIG_PACKAGE_sing-box=y$' .config
grep -q '^CONFIG_PACKAGE_xray-core=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-samba4=y$' .config
grep -q '^CONFIG_PACKAGE_samba4-server=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-ddns=y$' .config
grep -q '^CONFIG_PACKAGE_ddns-scripts=y$' .config
grep -q '^CONFIG_PACKAGE_luci-proto-wireguard=y$' .config
grep -q '^CONFIG_PACKAGE_wireguard-tools=y$' .config
grep -q '^CONFIG_PACKAGE_luci-app-zerotier=y$' .config
grep -q '^CONFIG_PACKAGE_zerotier=y$' .config
test -x files/etc/openclash/core/clash_meta

log_section "Download sources"
make download -j"$JOBS"

log_section "Build reusable host tools and cross-toolchain"
run_parallel_with_serial_retry tools/install
run_parallel_with_serial_retry toolchain/install

log_section "Compile CT3003 eMMC firmware"
if ! nice -n 5 make -j"$JOBS"; then
  echo "Parallel firmware build failed; retrying with -j1 V=s." >&2
  nice -n 5 make -j1 V=s
fi

rootfs_core="$(find build_dir -path '*/root-mediatek/etc/openclash/core/clash_meta' \
  -type f -perm -u+x -print -quit)"
if [[ -z "$rootfs_core" ]]; then
  echo "The embedded OpenClash core is missing from the firmware rootfs." >&2
  exit 1
fi

log_section "Collect and verify firmware"
BUILD_ID="$(date '+%Y%m%d-%H%M%S')"
RELEASE_DIR="$OUTPUT_ROOT/$BUILD_ID"
TARGET_DIR="$SOURCE_DIR/bin/targets/mediatek/filogic"
mkdir -p "$RELEASE_DIR"
find "$TARGET_DIR" -maxdepth 1 -type f -name '*cetron_ct3003-emmc*' \
  -exec cp -p {} "$RELEASE_DIR/" \;
cp .config "$RELEASE_DIR/build.config"
for metadata in profiles.json version.buildinfo; do
  if [[ -f "$TARGET_DIR/$metadata" ]]; then
    cp -p "$TARGET_DIR/$metadata" "$RELEASE_DIR/"
  fi
done

firmware="$(find "$RELEASE_DIR" -maxdepth 1 -type f \
  -name '*ct3003-emmc*sysupgrade.bin' -print -quit)"
if [[ -z "$firmware" ]]; then
  echo "CT3003 eMMC sysupgrade firmware was not generated." >&2
  exit 1
fi

manifest="$(find "$RELEASE_DIR" -maxdepth 1 -type f -name '*.manifest' -print -quit)"
for package in luci-app-openclash luci-app-samba4 luci-app-ddns \
  luci-proto-wireguard wireguard-tools luci-app-zerotier zerotier; do
  grep -q "^${package} " "$manifest"
done

(
  cd "$RELEASE_DIR"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | \
    sort | xargs sha256sum > SHA256SUMS
)
printf '%s\n' "$RELEASE_DIR" > "$OUTPUT_ROOT/LATEST"
ccache --show-stats || true
ls -lh "$RELEASE_DIR"
echo "Firmware ready: $firmware"

# CT3003 eMMC OpenWrt Builder

This repository builds an ImmortalWrt image for the Cetron CT3003 eMMC hardware using GitHub Actions.

## Included

- LuCI over HTTP with Argon theme
- OpenClash with an embedded ARM64 Mihomo core, plus PassWall2 with sing-box and Xray
- DDNS, Samba4, UPnP, SQM, statistics, Wake-on-LAN, TTYD, WireGuard and ZeroTier
- Default LAN IP: `192.168.6.1`
- Default login: `root` with no password

## Build and download

1. Open the **Actions** tab and choose **Build CT3003 eMMC firmware**.
2. Select **Run workflow**.
3. After it completes, download `CT3003-eMMC-firmware` from the run's artifacts. Manual builds also create a GitHub Release.

Repeat builds automatically reuse the download cache, compiler cache and the
cross-toolchain built for the exact same upstream source revision.

Only flash an image intended for the eMMC version of the CT3003. Keep a serial-recovery path available before changing firmware.

## Local build with OrbStack

The local builder mirrors the GitHub Actions package pins and firmware
configuration, but keeps the complete Linux build tree between runs. Downloads
and ccache data are stored persistently inside the OrbStack VM.

```bash
./scripts/orbstack-build.sh start
./scripts/orbstack-build.sh status
./scripts/orbstack-build.sh log
```

The default machine is `n60-openwrt-build`, with a conservative 12 parallel
jobs. Override these with `ORB_MACHINE` and `CT3003_JOBS`. Successful images are
copied to `outputs/orbstack/<timestamp>/`, and `outputs/orbstack/LATEST` records
the newest output directory.

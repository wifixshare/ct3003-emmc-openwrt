# CT3003 eMMC OpenWrt Builder

This repository builds an ImmortalWrt image for the Cetron CT3003 eMMC hardware using GitHub Actions.

## Included

- LuCI over HTTP with Argon theme
- OpenClash and PassWall2, including sing-box and Xray cores
- DDNS, Samba4, UPnP, SQM, statistics, Wake-on-LAN, TTYD and WireGuard LuCI support
- Default LAN IP: `192.168.6.1`
- Default login: `root` with no password

## Build and download

1. Open the **Actions** tab and choose **Build CT3003 eMMC firmware**.
2. Select **Run workflow**.
3. After it completes, download `CT3003-eMMC-firmware` from the run's artifacts. Manual builds also create a GitHub Release.

Repeat builds automatically reuse the download cache, compiler cache and the
cross-toolchain built for the exact same upstream source revision.

Only flash an image intended for the eMMC version of the CT3003. Keep a serial-recovery path available before changing firmware.

# IconAutoRefresh

A rootless iOS tweak for **Dopamine** (iOS 15.0 – 17.x) that automatically forces SpringBoard to refresh icon cache upon app installation.

## 🌟 Key Features

- **No Respring Needed:** Icons installed via Sileo, TrollStore Lite, or `dpkg` appear instantly.
- **Race Condition Safe:** Built-in delay ensures `mobileinstallation` finishes registration before triggering SBIconModel.
- **Rootless & A12+ Ready:** Full support for `arm64e` architectures and iOS 15–17 fallback selectors.

## 🛠 Installation

1. Download the latest `.deb` from the **Actions** tab.
2. Open and install via **Sileo** or **Zebra**.

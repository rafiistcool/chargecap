<p align="center">
  <img src="https://img.shields.io/badge/macOS-native-blue?style=flat-square&logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Swift-5.9+-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License" />
</p>

<h1 align="center">⚡ ChargeCap</h1>

<p align="center">
  <strong>Set it. Forget it. Save your battery.</strong><br/>
  A lightweight macOS menu bar app that stops charging at your desired percentage — keeping your battery healthy for years.
</p>

<p align="center">
  <img src="https://placehold.co/640x400/1a1a2e/e0e0e0?text=Screenshot+coming+soon" alt="ChargeCap Screenshot" width="640" />
</p>

---

## Features

- **🔋 Custom Charge Limit** — Set any stop percentage (e.g. 80%) to reduce wear on your battery cells
- **📦 Menu Bar App** — Lives quietly in your menu bar, no dock clutter
- **🚀 Auto-Start** — Runs at login so your limit is always enforced
- **🪶 Lightweight** — Minimal resource usage, built with native macOS frameworks
- **🖥️ Clean UI** — Simple, intuitive interface — no bloat

## Installation

### Download (Recommended)

Grab the latest `.dmg` from the [Releases](https://github.com/rafiistcool/chargecap/releases) page.

### Build from Source

```bash
git clone https://github.com/rafiistcool/chargecap.git
cd chargecap
xcodebuild -scheme ChargeCap -configuration Release
```

## How It Works

ChargeCap monitors your battery level using macOS's IOKit power APIs. When your battery reaches the configured limit, it sends a command to the SMC (System Management Controller) to pause charging. When the level drops below the threshold, charging resumes automatically.

> **Note:** On Apple Silicon Macs (M1/M2/M3/M4), ChargeCap uses the `charginglimit` SMC key. On Intel Macs, it uses the `BatteryChargeLimit` key. Both methods are safe and reversible.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac with SMC charging limit support
- Admin privileges (for SMC access)

## Usage

1. Launch ChargeCap — it appears in your menu bar
2. Click the icon and set your desired charge limit
3. That's it. ChargeCap handles the rest

To disable the limit, set it back to 100% or quit the app.

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

Please keep PRs focused and include a description of the change.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Made with ❤️ for your battery's sake
</p>

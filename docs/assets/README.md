# Design Assets

Source design files for ChargeCap app iconography.

## Files

| File | Description |
|------|-------------|
| `AppIcon.svg` | Master vector source for the macOS app icon. Blue → green gradient squircle with a white battery silhouette and a gradient shield + lightning bolt emblem. |

## Regenerating the app icon PNGs

The `Assets.xcassets/AppIcon.appiconset/` catalog ships the PNGs in every size
macOS requires (16, 32, 64, 128, 256, 512, 1024 px). To regenerate them from
`AppIcon.svg`:

```bash
pip install cairosvg
python3 - <<'PY'
import cairosvg, os
src = 'docs/assets/AppIcon.svg'
out = 'ChargeCap/Assets.xcassets/AppIcon.appiconset'
for s in (16, 32, 64, 128, 256, 512, 1024):
    cairosvg.svg2png(url=src, write_to=os.path.join(out, f'AppIcon-{s}.png'),
                     output_width=s, output_height=s)
PY
```

## Menu bar icons

The menu-bar icon is rendered directly from SF Symbols by
`ChargeCap/ChargeCapApp.swift` and `ChargeCap/Models/BatteryState.swift`. The
symbol is selected dynamically from the battery state and automatically adapts
to Light / Dark menu-bar appearance via the system template rendering:

| State | SF Symbol |
|-------|-----------|
| Charging | `battery.100.bolt` |
| Charge ≥ 76 % | `battery.100` |
| Charge 51–75 % (default) | `battery.75` |
| Charge 26–50 % | `battery.50` |
| Low battery (1–25 %) | `battery.25` |
| Depleted | `battery.0` |
| Charge-limit active | `bolt.slash.fill` |
| Sailing (discharge-to-resume, menu bar) | `sailboat.fill` |
| Sailing (in dropdown popover row) | `battery.100.bolt.rtl` |
| No battery (desktop Mac) | `desktopcomputer` |

## Color palette

| Name | Hex |
|------|------|
| Green (healthy) | `#34C759` |
| Blue (default) | `#007AFF` |
| Orange (warning) | `#FF9500` |
| Red (alert) | `#FF3B30` |

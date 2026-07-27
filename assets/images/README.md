# ProofIt App Assets

Source logo: `admin-panel/public/logo.png`

| File | Purpose |
|---|---|
| `logo.png` | Full logo (icon + text) — in-app splash screen |
| `splash_logo.png` | Full logo — native launch splash |
| `icon.png` | App icon (camera/pin/checkmark only) |
| `icon_foreground.png` | Android adaptive icon foreground |

Regenerate after updating the source logo:

```bash
# Re-crop from admin-panel/public/logo.png (or update assets manually), then:
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

# README artwork

- `masthead.svg`: original vector lettering and ornament, designed for GitHub's image renderer. No external fonts or remote assets required.
- `brief.png`: the real brief presentation components, rendered with fictional sample data and collapsed source sections.
- `settings.png`: the real Settings components rendered with sample preferences.

Regenerate the app previews from the repository root on macOS:

```sh
swift run DaybriefSnapshot docs/readme/brief.png --collapsed
swift run DaybriefSnapshot --settings --window --native brief docs/readme/settings.png
```

The screenshots use locally licensed Tiempos Text. The font binaries are not distributed; builds without them use the system serif. The painting is Camille Pissarro's *The Garden of the Tuileries on a Winter Afternoon* (1899), from the Met's public-domain collection. See the [artwork notes](../../App/Assets.xcassets/Art/README.md).

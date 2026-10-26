# Demo materials

GapSong's screenshots and `--demo` mode use a small set of **original** example
songs. They were written for this repository so the public source tree,
documentation images and demo builds do not contain third-party lyrics or
translations.

## Provenance

- The lyrics, Chinese translations and example sentences in
  `Sources/GapSong/DemoFixtures.swift` are original text written for GapSong.
- `Paper Lanterns` and `Signal Fires`, the artist `The Quiet Harbor`, and the
  album `Low Tide Letters` are fictional. They do not describe a real release.
- No audio recordings are bundled. Demo mode only injects text and a simulated
  playback position; it does not control Music.app.
- The demo fixtures are distributed under the same license as the rest of the
  repository.

## What uses them

| Fixture | Used by |
| --- | --- |
| `DemoFixtures.paperLanterns` | `preview.png`, `screenshot-full.png`, `practice*.png`, `favorites.png`, `mistakes.png` |
| `DemoFixtures.signalFires` | `--demo` track-change demonstration |

The snapshot commands in the README render these fixtures into
`docs/screenshots/`. The approved app icon (`docs/screenshots/icon.png`) is not
demo material and is unchanged.

## Real runtime is separate

Normal app runs still read the current track from Music.app and request lyrics
from [LRCLIB](https://lrclib.net/) at runtime. Demo fixtures are never used as a
fallback for real playback.

The network self-test makes one live LRCLIB request using the public-domain hymn
"Amazing Grace" (text by John Newton). The returned lyrics are not embedded in
the source tree or in screenshots.

## Scope

This document describes the deliberate demo fixture set above. It is not an
inventory of every string in the application.

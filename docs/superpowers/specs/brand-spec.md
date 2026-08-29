# TodApp — Brand & Asset Spec

Source of truth: `tod-prototype.html` (verified by direct source read, not memory), `:root` block lines 7–24.

## Color tokens

| Token | Hex | Usage |
|---|---|---|
| `--bg` | `#121014` | App background (this is the real background — not `#050406`, which only appears as decorative phone-bezel chrome elsewhere in the mockup, never as `--bg`) |
| `--surface` | `#1c1a20` | Card / panel surface |
| `--surface-2` | `#262129` | Elevated surface (inputs, chat bubbles) |
| `--surface-3` | `#302a33` | Disabled controls |
| `--line` | `#37313b` | Hairline borders |
| `--text` | `#f4efe6` | Primary text |
| `--text-dim` | `#a99fac` | Secondary text |
| `--text-faint` | `#6f6672` | Placeholder / disabled text |
| `--accent` | `#b3527a` | Primary accent (mauve-pink) — buttons, active states, focus rings |
| `--accent-soft` | `#b3527a` at 15% alpha (`26` hex suffix) | Accent glow/wash |
| `--accent-2` | `#e0b64a` | Gold — secondary accent, points/mono highlights |
| `--good` | `#5ad1a0` | Green — positive states, ratings |
| `--good-soft` | `#5ad1a0` at 13% alpha (`22` hex suffix) | Positive glow/wash |

## Typography

| Role | Font | Weights loaded | Fallback |
|---|---|---|---|
| Display (`--font-display`) | Unbounded | 600, 700, 800 | Arial Black, sans-serif |
| Body (`--font-body`) | Manrope | 400, 500, 600, 700, 800 | -apple-system, Segoe UI, sans-serif |
| Mono (`--font-mono`) | JetBrains Mono | 500, 600, 700 | ui-monospace, monospace |

SwiftUI mapping: bundle Unbounded/Manrope/JetBrains Mono as custom fonts (Google Fonts, OFL-licensed) via `Info.plist` `UIAppFonts`; fall back to `.rounded`/`.default`/`.monospaced` system design if a weight is missing.

## Structure (from source, not assumption)

Six tabs, German UI: **Heute** (today/post) · **Voten** (vote) · **Reveal** · **Rangliste** (leaderboard) · **Chat** · **Battle**.

Rating scale (`RATE_LABELS`, line 850): `-2 Aussetzer, -1 Naja, 0 Ok, 1 Gut, 2 Banger`, plus one Hidden-Gem pick per voter per round (`gemId`).

Battle modes (from `battle.active.mode` values in source data): `Frei`, `Künstler-Würfel`, `Aux Battle`.

This file satisfies huashu-design §1.a (Core Asset Protocol) for TodApp: all values above were read directly from `tod-prototype.html`, not recalled from memory.

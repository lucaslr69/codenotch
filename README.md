<div align="center">

# 🌀 Gauge

**A macOS app that pins a small dial to a screen edge, showing how much of each
coding assistant's usage limit you've burned — and whether it's still working,
done, or waiting on you.**

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black)
![Arch](https://img.shields.io/badge/arch-universal%20(Intel%20%2B%20Apple%20Silicon)-blue)
![Swift](https://img.shields.io/badge/swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

**Gauge** is a personal, minimalist fork of
[Codenotch](https://github.com/vinzdg/codenotch) by Vinz, backported to run on
**macOS 13 (Ventura)** and built as a **universal (Intel + Apple Silicon)**
binary, with its own look.

Hover a dial for its limit windows and when they reset. Claude's dial shows the
same **current session** window Claude Code's own `/usage` leads with, so the
two never disagree. A thin arc spins inside a provider's dial while a session is
busy, and the notch opens itself for a few seconds when an agent finishes or
stops to ask you something.

## What's different from Codenotch

- **macOS 13 (Ventura) and up.** Upstream requires macOS 15. The deployment
  target is 13.0 and every newer API is behind an availability check, so
  newer-OS flourishes (Liquid Glass, symbol effects, …) simply fall back at run
  time on Ventura.
- **Universal / Intel build.** A GitHub Actions workflow cross-compiles an
  `x86_64 + arm64` disk image that runs on Intel Macs.
- **The Gauge look.** The provider indicator is a **270° segmented dial** open
  at the bottom with a needle tip, in place of the original full ring; the
  accent is a calm **gauge teal (`#4FBFB3`)**; readings are monospaced; and the
  app and menu-bar icons are a gauge dial.
- **Auto-update off.** Sparkle is disabled — the official feed only serves
  macOS 15 builds, so a check here would only ever offer an update this copy
  can't run.

Everything else works as in upstream — the providers it reads (Claude Code,
Cursor, Codex, Copilot, Gemini, GLM, Grok, local Ollama / LM Studio, and more),
notch placement on any screen edge, session alerts, and the phone link. See the
[Codenotch README](https://github.com/vinzdg/codenotch#readme) for the full
provider list and the finer details of how each reading is sourced.

## Get it

There's no signed release; builds come from CI. Open the **Ventura Intel build**
workflow under this repo's **Actions** tab (it also runs on every push to
`ventura-intel`), download the artifact, unzip it, and open the `.dmg`. Drag
**Gauge** to `/Applications`, then clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Gauge.app
```

If macOS says the app is *damaged*, that's the quarantine flag rather than a bad
download — run the command above.

Universal binary, macOS 13 (Ventura) or later, Intel or Apple Silicon. The build
is ad-hoc signed (no Developer ID), so it is not notarized — hence the
quarantine step.

## Build from source

```sh
brew install xcodegen create-dmg   # once
make run                           # generate, build, launch a Debug build
make dmg-ci ARCH=x86_64            # the CI disk image (cross-compiles the Intel slice)
```

No signing identity is required. The product is **Gauge.app**, while the Xcode
target, scheme and bundle id stay `Codenotch` / `com.vinz.codenotch` on purpose:
CI, the login-keychain "Always Allow" grant and the stored preferences all key
off those, so renaming only the product keeps settings and builds intact.

Run with `CODENOTCH_DEMO=1` to see fixed sample data instead of live readings.

## Credits & license

Gauge is a fork of **[Codenotch](https://github.com/vinzdg/codenotch)** by Vinz
and its contributors. All of the original design, architecture and provider work
is theirs; this fork only backports it to macOS 13 / Intel and reskins it.

[MIT](LICENSE) © 2026 Vinz. Ventura/Intel fork ("Gauge") maintained by Lucas Roberto.

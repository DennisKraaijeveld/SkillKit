# Provider logo registry

Skillbook vendors provider marks in `macos/Skillbook/Assets.xcassets` so the app builds offline and does not depend on vendor URLs at runtime. `SkillHost` in `macos/Skillbook/Views/ProviderLogo.swift` is the source of truth for identifier, display name, asset name, and template rendering.

The repository and ownership survey behind this registry is in [`docs/research/provider-icons.md`](../research/provider-icons.md). It was verified against first-party sources on 2026-08-27.

## Supported identifiers

| Identifier | UI name | Owner | Official repository or product source | Asset |
| --- | --- | --- | --- | --- |
| `claude` | Claude | Anthropic | [`anthropics/claude-code`](https://github.com/anthropics/claude-code) | `LogoClaude` |
| `cursor` | Cursor | Anysphere | [`cursor/cursor`](https://github.com/cursor/cursor) | `LogoCursor` |
| `codex`, `openai` | Codex | OpenAI | [`openai/codex`](https://github.com/openai/codex) | `LogoOpenAI` |
| `opencode` | OpenCode | Anomaly | [`anomalyco/opencode`](https://github.com/anomalyco/opencode) | `LogoOpenCode` |
| `gemini` | Gemini | Google | [`google-gemini/gemini-cli`](https://github.com/google-gemini/gemini-cli) | `LogoGemini` |
| `copilot` | Copilot | GitHub | [`github/copilot-cli`](https://github.com/github/copilot-cli) | `LogoCopilot` |
| `windsurf` | Windsurf | Cognition | [Windsurf](https://windsurf.com/); public plugins remain under [`Exafunction`](https://github.com/Exafunction) | `LogoWindsurf` |
| `github` | GitHub | GitHub | [`github`](https://github.com/github) | `LogoGitHub` |
| `openclaw` | OpenClaw | OpenClaw Foundation | [`openclaw/openclaw`](https://github.com/openclaw/openclaw) | `LogoOpenClaw` |
| `crush` | Crush | Charmbracelet | [`charmbracelet/crush`](https://github.com/charmbracelet/crush) | `LogoCrush` |
| `devin` | Devin | Cognition | [`CognitionAI/devin-cli`](https://github.com/CognitionAI/devin-cli) | `LogoDevin` |
| `goose` | Goose | Agentic AI Foundation / Linux Foundation | [`aaif-goose/goose`](https://github.com/aaif-goose/goose) | `LogoGoose` |
| `kimchi` | Kimchi | Kimchi / CAST AI ecosystem | [`getkimchi/kimchi`](https://github.com/getkimchi/kimchi) | `LogoKimchi` |

Google Antigravity CLI is the current consumer successor to Gemini CLI, but it is not in this asset registry yet because Skillbook does not currently detect its skill directory. Add its icon together with detection support, rather than shipping an unused mark.

## Assets added or refreshed on 2026-08-27

| Asset | Exact upstream | Revision | Local transformation | SHA-256 |
| --- | --- | --- | --- | --- |
| `LogoCrush.png` | [`internal/ui/notification/crush-icon-solo.png`](https://github.com/charmbracelet/crush/blob/6d14dd93a9e526505f7de54ae5999431bc32a793/internal/ui/notification/crush-icon-solo.png) | `6d14dd93a9e526505f7de54ae5999431bc32a793` | None | `a41177d5afbdbc6838526d0a1b62076a686a18d2949e262eb405a2142dd082f2` |
| `LogoDevin.png` | [`app.devin.ai` PWA icon](https://app.devin.ai/assets/pwa/pwa-icon-192.png) | Retrieved 2026-08-27 | None | `e7b5e686afdb56f293a18d39365a25c1c062366763c87013189dc349927f2a1d` |
| `LogoGoose.png` | [`ui/desktop/src/images/iconTemplate@2x.png`](https://github.com/aaif-goose/goose/blob/caf59517cc280dd3523a80131f388024eaaede9d/ui/desktop/src/images/iconTemplate%402x.png) | `caf59517cc280dd3523a80131f388024eaaede9d` | None; upstream monochrome template asset | `4e9c40d0e5ad756a3349d5ff72df55e9c348ffe067c1da1eb6716f61dc964d10` |
| `LogoKimchi.png` | [Official `getkimchi` GitHub organization avatar](https://github.com/getkimchi.png?size=512) | Retrieved 2026-08-27 | None | `f623fab20dc6e80095c13493af2019ce0b47d08361154c16fe89c137424c374a` |
| `LogoCopilot.svg` | [`primer/octicons/icons/copilot-48.svg`](https://github.com/primer/octicons/blob/0e21a4c2d8449102f10e533d241f04797af0914c/icons/copilot-48.svg) | `0e21a4c2d8449102f10e533d241f04797af0914c` | None | `782ad9eaf1a90de204342ea185eb824483a36d5283b77339542ec11d9970495a` |

The other catalog assets predate this manifest and were not replaced in this pass. Their current first-party source recommendations and brand-policy links are recorded in the research note; do not claim an exact upstream revision for those local files until their hashes have been reconciled.

## Update contract

1. Prefer an official brand kit or an icon committed in the canonical repository. Use an official product favicon only when no maintained repository asset exists.
2. Copy the asset into the Xcode asset catalog; never hotlink a runtime UI image.
3. Keep color marks in original rendering mode. Use template rendering only for an upstream monochrome/template asset.
4. Record the exact source URL, retrieval date or commit, transformation, and SHA-256 here.
5. Product marks remain trademarks even when their source repositories use MIT, Apache-2.0, or FSL licenses. Use them only as small, nominative labels for the named tool and never to imply endorsement.

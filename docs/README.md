# KevLines — technical documentation

Supplements the main [README](../README.md). Start here for deep topics or AI/agent handoff; see also [**AGENTS.md**](../AGENTS.md) in the repo root.

| Document | Description |
|----------|-------------|
| [VideoOrientation.md](VideoOrientation.md) | **Saved-video decode & export orientation** — why Core Image + `preferredTransform` failed; why **AVMutableVideoComposition** + **AVAssetReaderVideoCompositionOutput** (v3.3.2+) is required; regression history; sanity checks. **Read before changing `VideoReader` or export dimensions.** |
| [Troubleshooting.md](Troubleshooting.md) | **Open issues & investigation goals** — version-stamped (e.g. v3.3.2): squat/hinge overlays on exported assessments, saved-video Row/Deadlift crashes; mitigations and next steps. |
| [UXBaseline.md](UXBaseline.md) | **Known-good UX baseline notes** before broader product changes that could affect user experience. |
| [Subscriptions.md](Subscriptions.md) | **RevenueCat + Supabase subscription setup** — product IDs, entitlement, auth linkage, promo codes, and sandbox checklist. |
| [WebBackend.md](WebBackend.md) | **Cross-device backend and web UI plan** — Supabase tables, RevenueCat webhook, promo redemption, account deletion, and Squarespace/web split. |
| [monetization/Monetization-Review.md](monetization/Monetization-Review.md) | **Pricing & monetization review** — competitor apps/prices, Kinetriq options A–E, ad vs subscription revenue scenarios; CSVs for Excel/Numbers. |

## Adding new docs

Place new topic files in this folder and add a one-line entry to the table above. For agent onboarding, also add a pointer in `AGENTS.md` if the topic is workflow-critical.

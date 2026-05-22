# Saved-video orientation (decoder → MediaPipe → export)

**Status:** Stable implementation since **v3.3.2** — `Sources/Core/Video/VideoReader.swift` uses **`AVMutableVideoComposition`** + **`AVAssetReaderVideoCompositionOutput`**. Handoff summary: [**AGENTS.md**](../AGENTS.md). Index of technical docs: [**docs/README.md**](README.md).

These notes record **why** exported analyzed videos once appeared upside-down, mirror-flipped, or with **left/right body sides swapped** relative to the clip in Photos—and **how we fixed it**—so future changes do not reintroduce the same bugs.

## What users expect

- The **pixels** fed to MediaPipe and drawn by `OverlayRenderer` must match **what Photos / QuickTime / AVPlayer show** for that file (same corner up, same left–right as on screen).
- **Body side** (`BodySide.left` / `.right`) is chosen from those display-oriented pixels. If decode orientation differs from what the user saw when picking a clip or choosing a side, landmarks look “wrong side.”

## What the file actually contains

- iPhone (and many) videos store a **native** pixel array (often landscape pixel dimensions) plus a **`preferredTransform`** on the video track. Players **do not** “rotate the file”; they rotate at **presentation** time.
- **MediaPipe does not read** container orientation tags—it sees raw buffers. So we must decode into **display-oriented** frames before pose + overlay.

## Approaches that caused regressions (do not resurrect)

### 1. `AVAssetReaderTrackOutput` + manual Core Image

Taking decoded buffers and applying `CIImage(cvPixelBuffer:).transformed(by: track.preferredTransform)` **does not** reproduce QuickTime’s output:

- **Core Image** uses a **bottom-left** origin; **CVPixelBuffer** rows are **top-first**.
- Ad‑hoc **vertical flips** before or after `preferredTransform` fixed one symptom (e.g. upside-down) and broke another (e.g. **horizontal mirror**, or upside-down again).
- Any fix built from flipping intuition tended to **compose badly** with rotation matrices.

**Lesson:** Do not “patch” orientation with extra `CGAffineTransform` flips around CIImage without using the same math as AVFoundation’s compositor.

### 2. Per-frame flips in `OverlayRenderer`

`OverlayRenderer` only flips the **Core Graphics** context so **normalized overlay coordinates** (y-down, 0…1) match the buffer. It does not correct **source video** orientation. If decode is wrong, overlay and video stay **internally consistent** but the **whole file** is still wrong vs Photos.

**Lesson:** Wrong export orientation is almost always **upstream** of overlay (reader), not the overlay renderer.

### 3. Relying on `AVAssetWriter` `transform` to fix bad pixels

If pixels are already wrong, writing with a non-identity `transform` may help **some** players but keeps analysis and user expectation misaligned. We bake correct pixels and keep **`videoInput.transform = .identity`** (see `VideoWriter`).

## Correct approach (current design, v3.3.2+)

Use **`AVMutableVideoComposition`** + **`AVAssetReaderVideoCompositionOutput`**:

1. **`AVMutableComposition`** — insert the video track’s time range.
2. **`AVMutableVideoComposition`** — set `renderSize` from the axis-aligned bounds of `CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)` (use absolute width/height).
3. **`AVMutableVideoCompositionLayerInstruction`** — `setTransform(_:at:)` with **`preferredTransform` concatenated with a translation** that moves the transformed rect into **positive x/y** (same pattern as Apple’s editing/composition samples).
4. Read BGRA frames from **`AVAssetReaderVideoCompositionOutput`** with `videoComposition` set.

That path uses the **same orientation pipeline** as system playback, so decoded frames match the library UI.

**Code:** `Sources/Core/Video/VideoReader.swift`

## Encoder / writer

- **`VideoWriter`** dimensions must match **`VideoReader`’s** `outputWidth` / `outputHeight` (display-oriented).
- **`outputTransform`** stays **identity** because orientation is already baked into each pixel buffer.

## Quick sanity checks after changing decode

1. Export the same clip analyzed in KevLines and open it next to the **original** in QuickTime—same **up** direction, no mirror, **left/right** of the subject matches.
2. Toggle **Left vs Right** on a side-specific exercise—the highlighted limb matches the side you expect from the **processed** video.
3. If orientation bugs return, **suspect `VideoReader` first**, not analyzers or `OverlayRenderer`.

## Version history (short)

| Version | Approach | Typical failure |
|--------|------------|-----------------|
| Pre–3.3 | CI + `preferredTransform` only | Upside-down vs Photos |
| 3.3.0 | + vertical flip after rotation | Often fixed upright; **mirror** |
| 3.3.1 | Vertical flip **before** rotation | Upright/mirror traded; still inconsistent |
| **3.3.2+** | **Video composition output** | Aligned with system players |

## References

- Apple: *AVFoundation Programming Guide* — reading time-based media, video composition.
- In-repo implementation: `Sources/Core/Video/VideoReader.swift`, `Sources/Core/Video/VideoWriter.swift`, `Sources/Core/Video/VideoProcessor.swift`.

import Foundation
import simd

/// Generates overlay instructions for a derived spine polyline.
/// MediaPipe has no explicit spine landmarks, so we approximate using:
///   Cervical (ear) → Upper thoracic (shoulder) → Mid-thoracic (interpolated) → Lumbar (hip)
struct SpineOverlay {

    /// Build spine overlay instructions from available landmark positions.
    /// - Parameters:
    ///   - ear: Cervical proxy (ear on active side, or bilateral midpoint). Nil if not visible.
    ///   - shoulder: Upper thoracic anchor (shoulder or bilateral midpoint).
    ///   - hip: Lumbar/sacral anchor (hip or bilateral midpoint).
    ///   - color: Line and dot color (default magenta to distinguish from skeleton).
    ///   - lineWidth: Spine line thickness.
    ///   - showDots: Whether to draw small circles at each spine point.
    static func instructions(
        ear: SIMD2<Float>?,
        shoulder: SIMD2<Float>,
        hip: SIMD2<Float>,
        color: OverlayColor = .spine,
        lineWidth: Float = 2.0,
        showDots: Bool = true
    ) -> [OverlayInstruction] {
        let midSpine = (shoulder + hip) / 2.0

        var result: [OverlayInstruction] = []

        // Cervical → upper thoracic
        if let ear {
            result.append(.line(from: ear, to: shoulder, color: color, width: lineWidth))
        }

        // Upper thoracic → mid-thoracic → lumbar
        result.append(.line(from: shoulder, to: midSpine, color: color, width: lineWidth))
        result.append(.line(from: midSpine, to: hip, color: color, width: lineWidth))

        if showDots {
            let dotRadius: Float = 6
            if let ear {
                result.append(.circle(at: ear, radius: dotRadius, color: color, filled: true))
            }
            result.append(.circle(at: shoulder, radius: dotRadius, color: color, filled: true))
            result.append(.circle(at: midSpine, radius: dotRadius, color: color, filled: true))
            result.append(.circle(at: hip, radius: dotRadius, color: color, filled: true))
        }

        return result
    }
}

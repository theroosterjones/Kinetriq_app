import Foundation
import simd

struct AngleCalculator {

    /// Compute the interior angle at vertex `b` formed by rays b→a and b→c.
    /// Returns degrees in the range [0, 180].
    /// Uses 2D screen coordinates — camera-angle-dependent.
    static func angle(a: SIMD2<Float>, b: SIMD2<Float>, c: SIMD2<Float>) -> Float {
        let radians = atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x)
        var deg = abs(radians * 180.0 / .pi)
        if deg > 180.0 { deg = 360.0 - deg }
        return deg
    }

    /// Integer degrees safe for UI strings. Plain `Int(nonFinite)` traps at runtime in Swift.
    static func displayDegrees(_ degrees: Float) -> Int {
        guard degrees.isFinite else { return 0 }
        return Int(degrees.rounded(.towardZero))
    }

    /// Compute the true 3D interior angle at vertex `b` using metric world coordinates.
    /// Camera-position-independent. Returns degrees in the range [0, 180].
    static func angle3D(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) -> Float {
        let e1 = a - b
        let e2 = c - b
        guard simd_length_squared(e1) > 1e-12, simd_length_squared(e2) > 1e-12 else {
            return .nan
        }
        let v1 = simd_normalize(e1)
        let v2 = simd_normalize(e2)
        // Clamp to [-1, 1] to guard against floating-point drift past the acos domain
        let cosTheta = max(-1.0, min(1.0, simd_dot(v1, v2)))
        return acos(cosTheta) * 180.0 / .pi
    }

    /// Extend the line through `p1` and `p2` in both directions until it hits the
    /// frame boundary defined by (0,0)–(width, height). Returns the two intersection points.
    static func extendLineToFrame(
        p1: SIMD2<Float>,
        p2: SIMD2<Float>,
        width: Float,
        height: Float
    ) -> (SIMD2<Float>, SIMD2<Float>) {
        let seg = p2 - p1
        guard simd_length_squared(seg) > 1e-8 else {
            return (p1, p2)
        }
        let dir = simd_normalize(seg)
        let forward  = edgeIntersection(origin: p1, direction: dir, width: width, height: height)
        let backward = edgeIntersection(origin: p2, direction: -dir, width: width, height: height)
        return (forward ?? p1, backward ?? p2)
    }

    // MARK: - Private

    private static func edgeIntersection(
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        width: Float,
        height: Float
    ) -> SIMD2<Float>? {
        var bestT: Float = .greatestFiniteMagnitude
        var bestPoint: SIMD2<Float>?

        let edges: [(axis: WritableKeyPath<SIMD2<Float>, Float>,
                      cross: WritableKeyPath<SIMD2<Float>, Float>,
                      value: Float, crossMax: Float)] = [
            (\.y, \.x, 0,      width),   // top
            (\.y, \.x, height, width),    // bottom
            (\.x, \.y, 0,      height),   // left
            (\.x, \.y, width,  height)    // right
        ]

        for edge in edges {
            let dAxis = direction[keyPath: edge.axis]
            guard dAxis != 0 else { continue }
            let t = (edge.value - origin[keyPath: edge.axis]) / dAxis
            guard t > 0 else { continue }
            let crossVal = origin[keyPath: edge.cross] + t * direction[keyPath: edge.cross]
            guard crossVal >= 0, crossVal <= edge.crossMax else { continue }
            if t < bestT {
                bestT = t
                var pt = SIMD2<Float>.zero
                pt[keyPath: edge.axis] = edge.value
                pt[keyPath: edge.cross] = crossVal
                bestPoint = pt
            }
        }
        return bestPoint
    }
}

/// Geometry helper for drawing a joint marker on the bony "tip" of a bent joint —
/// the olecranon (point of the elbow) or the patella/point of the knee — instead
/// of the anatomical rotation center MediaPipe reports.
///
/// In the sagittal (side) view the tip sits on the convex side of the bend, which
/// is the direction opposite the interior bisector of the two adjacent limb
/// segments. Tracking the tip reads as more stable and anatomically correct on
/// screen; it is display-only and never used for angle or rep calculations.
enum JointTip {

    /// - Parameters:
    ///   - vertex: the joint landmark (elbow or knee).
    ///   - a, b: the two adjacent joints (e.g. shoulder & wrist, or hip & ankle).
    ///   - offset: fraction of the shorter adjacent segment to push outward.
    /// - Returns: the offset tip position, or `vertex` when the limb is nearly
    ///   straight (no well-defined tip direction) or the input is degenerate.
    static func position(
        vertex: SIMD2<Float>,
        toward a: SIMD2<Float>,
        and b: SIMD2<Float>,
        offset: Float = 0.18
    ) -> SIMD2<Float> {
        let v1 = a - vertex
        let v2 = b - vertex
        let l1 = simd_length(v1)
        let l2 = simd_length(v2)
        guard l1 > 1e-5, l2 > 1e-5 else { return vertex }

        let bisector = (v1 / l1) + (v2 / l2)
        let bl = simd_length(bisector)
        // Near-straight limb → the tip direction is undefined; stay on the vertex.
        guard bl > 1e-3 else { return vertex }

        let outward = -(bisector / bl)
        return vertex + outward * (offset * min(l1, l2))
    }
}

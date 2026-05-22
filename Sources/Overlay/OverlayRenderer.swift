import CoreGraphics
import CoreVideo
import CoreText
import simd

/// Renders overlay instructions directly onto a CVPixelBuffer using Core Graphics.
/// Replaces OpenCV's cv2.line, cv2.circle, cv2.putText drawing calls.
final class OverlayRenderer {

    func render(instructions: [OverlayInstruction], onto pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        guard let context = CGContext(
            data: baseAddress,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        // Core Graphics origin is bottom-left; video frames are top-left.
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)

        let fw = Float(w)
        let fh = Float(h)

        for instruction in instructions {
            switch instruction {
            case .line(let from, let to, let color, let lineWidth):
                drawLine(context: context, from: from, to: to, color: color,
                         lineWidth: lineWidth, width: fw, height: fh)

            case .extendedLine(let from, let through, let color, let lineWidth):
                let fromPx = SIMD2<Float>(from.x * fw, from.y * fh)
                let throughPx = SIMD2<Float>(through.x * fw, through.y * fh)
                let (p1, p2) = AngleCalculator.extendLineToFrame(
                    p1: fromPx, p2: throughPx, width: fw, height: fh
                )
                drawLinePx(context: context, from: p1, to: p2, color: color, lineWidth: lineWidth)

            case .circle(let center, let radius, let color, let filled):
                drawCircle(context: context, center: center, radius: radius,
                           color: color, filled: filled, width: fw, height: fh)

            case .text(let string, let position, let color, let size):
                drawText(context: context, text: string, at: position,
                         color: color, size: size, width: fw, height: fh)
            }
        }
    }

    // MARK: - Drawing Primitives

    private func drawLine(context: CGContext, from: SIMD2<Float>, to: SIMD2<Float>,
                          color: OverlayColor, lineWidth: Float, width: Float, height: Float) {
        let fromPx = SIMD2<Float>(from.x * width, from.y * height)
        let toPx = SIMD2<Float>(to.x * width, to.y * height)
        drawLinePx(context: context, from: fromPx, to: toPx, color: color, lineWidth: lineWidth)
    }

    private func drawLinePx(context: CGContext, from: SIMD2<Float>, to: SIMD2<Float>,
                            color: OverlayColor, lineWidth: Float) {
        let (r, g, b, a) = color.rgba
        context.setStrokeColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        context.setLineWidth(CGFloat(lineWidth))
        context.move(to: CGPoint(x: CGFloat(from.x), y: CGFloat(from.y)))
        context.addLine(to: CGPoint(x: CGFloat(to.x), y: CGFloat(to.y)))
        context.strokePath()
    }

    private func drawCircle(context: CGContext, center: SIMD2<Float>, radius: Float,
                            color: OverlayColor, filled: Bool, width: Float, height: Float) {
        let cx = CGFloat(center.x * width)
        let cy = CGFloat(center.y * height)
        let r = CGFloat(radius)
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)

        let (rv, gv, bv, av) = color.rgba
        if filled {
            context.setFillColor(red: CGFloat(rv), green: CGFloat(gv), blue: CGFloat(bv), alpha: CGFloat(av))
            context.fillEllipse(in: rect)
        } else {
            context.setStrokeColor(red: CGFloat(rv), green: CGFloat(gv), blue: CGFloat(bv), alpha: CGFloat(av))
            context.setLineWidth(2)
            context.strokeEllipse(in: rect)
        }
    }

    private func drawText(context: CGContext, text: String, at position: SIMD2<Float>,
                          color: OverlayColor, size: Float, width: Float, height: Float) {
        let x = CGFloat(position.x * width)
        let y = CGFloat(position.y * height)
        let (r, g, b, a) = color.rgba

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(size), nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)

        context.saveGState()
        // Un-flip y locally so Core Text glyphs render right-side-up
        context.translateBy(x: x, y: y)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

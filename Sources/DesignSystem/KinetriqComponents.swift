import SwiftUI

// MARK: - Reusable building blocks for the Kinetriq v2 UI.
//
// These are intentionally small, composable, and visual-only so screens can be
// assembled quickly with a consistent premium look. None of them touch the
// analysis pipeline.

// MARK: Card container

struct KCard<Content: View>: View {
    var padding: CGFloat = KSpacing.md
    var elevated: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KRadius.md, style: .continuous)
                    .strokeBorder(KColor.separator.opacity(0.6), lineWidth: 0.75)
            )
            .modifier(ConditionalShadow(elevated: elevated))
    }
}

private struct ConditionalShadow: ViewModifier {
    let elevated: Bool
    func body(content: Content) -> some View {
        if elevated { content.kSoftShadow() } else { content }
    }
}

// MARK: Section header

struct SectionHeader<Trailing: View>: View {
    let eyebrow: String?
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, eyebrow: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.eyebrow = eyebrow
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(KFont.eyebrow)
                        .foregroundStyle(KColor.accent)
                        .tracking(0.8)
                }
                Text(title)
                    .font(KFont.title2)
                    .foregroundStyle(KColor.textPrimary)
            }
            Spacer()
            trailing
        }
    }
}

// MARK: Eyebrow label

struct Eyebrow: View {
    let text: String
    var color: Color = KColor.textTertiary
    var body: some View {
        Text(text.uppercased())
            .font(KFont.eyebrow)
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

// MARK: Buttons

struct KPrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = KColor.brandGradient
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KFont.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(gradient, in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct KSecondaryButtonStyle: ButtonStyle {
    var tint: Color = KColor.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(KFont.callout)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: Score ring

struct ScoreRing: View {
    /// 0–100 value.
    let value: Int
    var size: CGFloat = 132
    var lineWidth: CGFloat = 12
    var caption: String? = "SCORE"

    private var fraction: CGFloat { CGFloat(max(0, min(100, value))) / 100 }
    private var color: Color { KColor.score(value) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(KColor.separator.opacity(0.5), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(value)")
                    .font(KFont.numeral(size * 0.34))
                    .foregroundStyle(KColor.textPrimary)
                    .monospacedDigit()
                if let caption {
                    Text(caption)
                        .font(KFont.micro)
                        .foregroundStyle(KColor.textTertiary)
                        .tracking(1.2)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: Grade badge

struct GradeBadge: View {
    let grade: LetterGrade
    var size: CGFloat = 64

    var body: some View {
        Text(grade.rawValue)
            .font(KFont.numeral(size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [KColor.grade(grade).opacity(0.85), KColor.grade(grade)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .shadow(color: KColor.grade(grade).opacity(0.4), radius: 10, x: 0, y: 6)
    }
}

// MARK: Stat tile

struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = KColor.accent

    var body: some View {
        VStack(alignment: .leading, spacing: KSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(KFont.numeral(24))
                .foregroundStyle(KColor.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(KFont.caption)
                .foregroundStyle(KColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KSpacing.md)
        .background(KColor.surfaceSunken, in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
    }
}

// MARK: Metric chip

struct MetricChip: View {
    let label: String
    let value: String
    var tint: Color = KColor.textSecondary

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(KFont.caption)
                .foregroundStyle(KColor.textTertiary)
            Text(value)
                .font(KFont.callout)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, KSpacing.sm)
        .padding(.vertical, 8)
        .background(KColor.surfaceSunken, in: Capsule())
    }
}

// MARK: Pill / tag

struct KPill: View {
    let text: String
    var tint: Color = KColor.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(KFont.micro)
            .tracking(0.4)
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)), in: Capsule())
    }
}

// MARK: Info banner

struct InfoBanner: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = KColor.accent

    var body: some View {
        HStack(alignment: .top, spacing: KSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textPrimary)
                Text(message)
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(KSpacing.md)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: Linear progress track

struct ProgressTrack: View {
    /// 0–1
    let value: Double
    var tint: Color = KColor.accent
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(KColor.separator.opacity(0.6))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: Sparkline (lightweight trend chart, no dependencies)

struct Sparkline: View {
    let values: [Double]
    var tint: Color = KColor.accent
    var showFill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if showFill, pts.count > 1 {
                    fillPath(pts, in: geo.size)
                        .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.0)],
                                             startPoint: .top, endPoint: .bottom))
                }
                linePath(pts)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        let range = max(maxV - minV, 0.0001)
        return values.enumerated().map { idx, v in
            let x = size.width * CGFloat(idx) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat((v - minV) / range))
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        pts.dropFirst().forEach { p.addLine(to: $0) }
        return p
    }

    private func fillPath(_ pts: [CGPoint], in size: CGSize) -> Path {
        var p = linePath(pts)
        if let last = pts.last, let first = pts.first {
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.addLine(to: CGPoint(x: first.x, y: size.height))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: Empty / coming-soon state

struct KEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = KColor.accent

    var body: some View {
        VStack(spacing: KSpacing.md) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(KFont.title2)
                .foregroundStyle(KColor.textPrimary)
            Text(message)
                .font(KFont.subheadline)
                .foregroundStyle(KColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(KSpacing.lg)
    }
}

// MARK: Screen background

struct KScreenBackground: View {
    var body: some View {
        KColor.background.ignoresSafeArea()
    }
}

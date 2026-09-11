import SwiftUI

/// Renders the technique lessons a set actually earned.
///
/// Shown under the results rather than in a browsable library, because the thing
/// that makes it worth reading is that it is about the set on screen.
struct TechniqueLessonSection: View {
    let lessons: [TechniqueLesson]
    var showsHeader = true

    var body: some View {
        if !lessons.isEmpty {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                if showsHeader {
                    SectionHeader("Work on this", eyebrow: "From your own reps")
                }
                ForEach(lessons) { lesson in
                    TechniqueLessonCard(lesson: lesson)
                }
            }
        }
    }
}

struct TechniqueLessonCard: View {
    let lesson: TechniqueLesson
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: KSpacing.sm) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.title)
                            .font(KFont.callout)
                            .foregroundStyle(KColor.textPrimary)
                            .multilineTextAlignment(.leading)
                        if !expanded {
                            Text(lesson.why)
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(KColor.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(lesson.why)
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let asset = lesson.illustrationAsset, UIImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
                }

                VStack(alignment: .leading, spacing: KSpacing.xs) {
                    ForEach(Array(lesson.cues.enumerated()), id: \.offset) { _, cue in
                        HStack(alignment: .top, spacing: KSpacing.xs) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tint)
                                .frame(width: 14)
                                .padding(.top, 3)
                            Text(cue)
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let drill = lesson.drill {
                    HStack(alignment: .top, spacing: KSpacing.xs) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KColor.teal)
                            .frame(width: 14)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Try this")
                                .font(KFont.micro)
                                .foregroundStyle(KColor.teal)
                            Text(drill)
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(KSpacing.sm)
                    .background(KColor.teal.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
                }

                if let attribution = lesson.attribution {
                    Text(attribution)
                        .font(.system(size: 10))
                        .foregroundStyle(KColor.textTertiary)
                }
            }
        }
        .padding(KSpacing.md)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KRadius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var icon: String {
        switch lesson.fault {
        case .rushedEccentric:        return "hare.fill"
        case .inconsistentDepth:      return "arrow.up.and.down.circle.fill"
        case .acceleratingTempo:      return "metronome.fill"
        case .rangeBelowPersonalBest: return "arrow.down.right.circle.fill"
        case .asymmetry:              return "arrow.left.arrow.right"
        case .lowTracking:            return "video.slash.fill"
        case .tooFewReps:             return "number"
        }
    }

    private var tint: Color {
        switch lesson.fault {
        case .lowTracking, .tooFewReps: return KColor.accent
        case .asymmetry:                return KColor.violet
        default:                        return KColor.warning
        }
    }
}

import SwiftUI

struct ExerciseLibraryView: View {
    @EnvironmentObject private var router: AppRouter

    @State private var query: String
    @State private var category: ExerciseLibrary.Category = .all
    @State private var selectedItem: ExerciseLibrary.Item?

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    private var results: [ExerciseLibrary.Item] {
        ExerciseLibrary.filtered(category: category, query: query)
    }

    private let columns = [
        GridItem(.flexible(), spacing: KSpacing.sm),
        GridItem(.flexible(), spacing: KSpacing.sm)
    ]

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(spacing: KSpacing.md) {
                    searchField
                    categoryChips
                    if results.isEmpty {
                        KEmptyState(icon: "magnifyingglass",
                                    title: "No matches",
                                    message: "Try a different exercise name or category.")
                            .padding(.top, KSpacing.xl)
                    } else {
                        LazyVGrid(columns: columns, spacing: KSpacing.sm) {
                            ForEach(results) { item in
                                Button { selectedItem = item } label: { card(item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.bottom, KSpacing.xxl)
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedItem) { item in
            ExerciseDetailSheet(item: item)
        }
    }

    private var searchField: some View {
        HStack(spacing: KSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(KColor.textTertiary)
            TextField("Search movements", text: $query)
                .font(KFont.body)
                .foregroundStyle(KColor.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KColor.textTertiary)
                }
            }
        }
        .padding(.horizontal, KSpacing.md)
        .frame(height: 48)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous)
                .strokeBorder(KColor.separator.opacity(0.6), lineWidth: 0.75)
        )
        .padding(.top, KSpacing.xs)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KSpacing.xs) {
                ForEach(ExerciseLibrary.Category.allCases) { cat in
                    let isOn = cat == category
                    Button {
                        withAnimation(.snappy) { category = cat }
                    } label: {
                        Text(cat.rawValue)
                            .font(KFont.callout)
                            .foregroundStyle(isOn ? .white : KColor.textSecondary)
                            .padding(.horizontal, KSpacing.md)
                            .padding(.vertical, 9)
                            .background(
                                isOn ? AnyShapeStyle(KColor.accent) : AnyShapeStyle(KColor.surface),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(KColor.separator.opacity(isOn ? 0 : 0.6), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func card(_ item: ExerciseLibrary.Item) -> some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            HStack {
                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 46, height: 46)
                    .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
                Spacer()
                if item.assessmentType != nil {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(KColor.violet)
                }
            }
            Text(item.displayName)
                .font(KFont.callout)
                .foregroundStyle(KColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 11, weight: .semibold))
                Text(item.plane)
                    .font(KFont.caption)
            }
            .foregroundStyle(KColor.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(KSpacing.md)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KRadius.md, style: .continuous)
                .strokeBorder(KColor.separator.opacity(0.6), lineWidth: 0.75)
        )
        .kSoftShadow()
    }
}

// MARK: - Detail sheet

private struct ExerciseDetailSheet: View {
    let item: ExerciseLibrary.Item
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            KScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: KSpacing.lg) {
                    header
                    KCard {
                        VStack(alignment: .leading, spacing: KSpacing.sm) {
                            Eyebrow(text: "What it measures")
                            Text(item.summary)
                                .font(KFont.body)
                                .foregroundStyle(KColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    cuesCard
                    Spacer(minLength: KSpacing.xl)
                }
                .padding(.horizontal, KSpacing.screenH)
                .padding(.top, KSpacing.lg)
                .padding(.bottom, 110)
            }

            VStack {
                Spacer()
                analyzeButton
                    .padding(.horizontal, KSpacing.screenH)
                    .padding(.bottom, KSpacing.md)
                    .background(
                        LinearGradient(colors: [KColor.background.opacity(0), KColor.background],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                    )
            }
        }
    }

    private var header: some View {
        HStack(spacing: KSpacing.md) {
            Image(systemName: item.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 72, height: 72)
                .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: KRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayName)
                    .font(KFont.title2)
                    .foregroundStyle(KColor.textPrimary)
                HStack(spacing: 6) {
                    KPill(text: item.category.rawValue, tint: item.tint)
                    KPill(text: item.plane, tint: KColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var cuesCard: some View {
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.sm) {
                Eyebrow(text: "Camera & coaching cues")
                ForEach(item.cues, id: \.self) { cue in
                    HStack(alignment: .top, spacing: KSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(item.tint)
                        Text(cue)
                            .font(KFont.subheadline)
                            .foregroundStyle(KColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var analyzeButton: some View {
        if item.exerciseType != nil || item.assessmentType != nil {
            Button {
                if let ex = item.exerciseType {
                    router.analyze(exercise: ex)
                } else if let asmt = item.assessmentType {
                    router.analyze(assessment: asmt)
                }
                dismiss()
            } label: {
                Label("Analyze this movement", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(KPrimaryButtonStyle())
        }
    }
}

import SwiftUI
import SwiftData

/// Progress tab — real history, backed by SwiftData.
///
/// This screen previously rendered hardcoded sample sparklines behind a "Progress
/// sync is coming" banner because nothing was ever persisted. Every number below now
/// comes from saved `AnalysisRecord` rows.
struct WorkoutHistoryView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AnalysisRecord.date, order: .reverse)
    private var records: [AnalysisRecord]

    /// `nil` means "all movements". Trends need a single movement to be meaningful —
    /// a squat score and a curl score are not the same measurement.
    @State private var selectedMovementKey: String?
    @State private var sharePayload: SharePayload?
    @State private var showingDeleteAllConfirmation = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                KScreenBackground()
                if records.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        overflowMenu
                    }
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(items: payload.items)
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .confirmationDialog(
                "Delete all saved analyses?",
                isPresented: $showingDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    AnalysisLibrary.deleteAll(from: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every saved session and its video from this device. It cannot be undone.")
            }
        }
    }

    // MARK: - Derived data

    /// Movements that actually appear in history, newest activity first.
    private var availableMovements: [(key: String, name: String)] {
        var seen = Set<String>()
        var result: [(key: String, name: String)] = []
        for record in records where !seen.contains(record.movementKey) {
            seen.insert(record.movementKey)
            result.append((record.movementKey, record.movementName))
        }
        return result
    }

    /// The movement the trend charts describe. Defaults to whatever was analyzed most
    /// recently so the screen is useful without touching the filter.
    private var focusMovementKey: String? {
        selectedMovementKey ?? records.first?.movementKey
    }

    private var focusMovementName: String {
        availableMovements.first { $0.key == focusMovementKey }?.name ?? "All movements"
    }

    /// Oldest-first history for the focused movement — the order trends read in.
    private var focusHistory: [AnalysisRecord] {
        guard let focusMovementKey else { return [] }
        return records
            .filter { $0.movementKey == focusMovementKey }
            .reversed()
    }

    private var filteredRecords: [AnalysisRecord] {
        guard let selectedMovementKey else { return records }
        return records.filter { $0.movementKey == selectedMovementKey }
    }

    // MARK: - Layout

    private var content: some View {
        ScrollView {
            VStack(spacing: KSpacing.lg) {
                movementPicker
                trendInsightsCard
                scoreTrendCard
                depthTrendCard
                activityCard
                sessionList
            }
            .padding(.horizontal, KSpacing.screenH)
            .padding(.top, KSpacing.xs)
            .padding(.bottom, KSpacing.xxl)
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                exportCSV(scope: .all)
            } label: {
                Label("Export all as CSV", systemImage: "square.and.arrow.up")
            }
            if selectedMovementKey != nil {
                Button {
                    exportCSV(scope: .filtered)
                } label: {
                    Label("Export \(focusMovementName) as CSV", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                exportCSV(scope: .perRep)
            } label: {
                Label("Export per-rep detail as CSV", systemImage: "tablecells")
            }
            Divider()
            Button(role: .destructive) {
                showingDeleteAllConfirmation = true
            } label: {
                Label("Delete all history", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var movementPicker: some View {
        Menu {
            Button {
                selectedMovementKey = nil
            } label: {
                if selectedMovementKey == nil {
                    Label("All movements", systemImage: "checkmark")
                } else {
                    Text("All movements")
                }
            }
            Divider()
            ForEach(availableMovements, id: \.key) { movement in
                Button {
                    selectedMovementKey = movement.key
                } label: {
                    if selectedMovementKey == movement.key {
                        Label(movement.name, systemImage: "checkmark")
                    } else {
                        Text(movement.name)
                    }
                }
            }
        } label: {
            HStack(spacing: KSpacing.xs) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(KColor.accent)
                Text(selectedMovementKey == nil ? "All movements" : focusMovementName)
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KColor.textTertiary)
            }
            .padding(.horizontal, KSpacing.md)
            .frame(height: 48)
            .background(KColor.surface, in: RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KRadius.sm, style: .continuous)
                    .strokeBorder(KColor.separator.opacity(0.6), lineWidth: 0.75)
            )
        }
        .padding(.top, KSpacing.xs)
    }

    // MARK: Trend coaching

    @ViewBuilder
    private var trendInsightsCard: some View {
        let insights = TrendInsights.insights(
            for: focusHistory.map(TrendSample.init(record:)),
            movementName: focusMovementName
        )
        if !insights.isEmpty {
            KCard {
                VStack(alignment: .leading, spacing: KSpacing.sm) {
                    SectionHeader("Across sessions", eyebrow: focusMovementName)
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: KSpacing.xs) {
                            Image(systemName: insight.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(tint(insight.tone))
                                .frame(width: 18)
                                .padding(.top, 1)
                            Text(insight.text)
                                .font(KFont.caption)
                                .foregroundStyle(KColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func tint(_ tone: InsightTone) -> Color {
        switch tone {
        case .positive: return KColor.success
        case .caution: return KColor.warning
        case .info: return KColor.accent
        }
    }

    // MARK: Score trend

    @ViewBuilder
    private var scoreTrendCard: some View {
        let scores = focusHistory.compactMap { $0.finalScore }
        KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Consistency score")
                        Text(focusMovementName)
                            .font(KFont.headline)
                            .foregroundStyle(KColor.textPrimary)
                    }
                    Spacer()
                    if scores.count > 1 {
                        KPill(text: "\(scores.count) scored sets", tint: KColor.textTertiary)
                    }
                }

                if scores.count > 1 {
                    Sparkline(values: scores.map(Double.init), tint: KColor.accent)
                        .frame(height: 80)
                    HStack(spacing: KSpacing.sm) {
                        StatTile(icon: trendIcon(scores),
                                 value: trendValue(scores),
                                 label: "Change",
                                 tint: trendColor(scores))
                        StatTile(icon: "rosette",
                                 value: "\(scores.max() ?? 0)",
                                 label: "Best",
                                 tint: KColor.accent)
                        StatTile(icon: "function",
                                 value: "\(Int(Double(scores.reduce(0, +)) / Double(scores.count)))",
                                 label: "Average",
                                 tint: KColor.teal)
                    }
                } else {
                    notEnoughData(
                        "Scores need at least three clean reps per set. Analyze this movement a couple more times and the trend appears here."
                    )
                }
            }
        }
    }

    /// First-to-last change. Deliberately not a regression line — with the handful of
    /// sessions most users will have, a fitted slope reads as more precision than the
    /// data supports.
    private func trendDelta(_ scores: [Int]) -> Int {
        guard let first = scores.first, let last = scores.last else { return 0 }
        return last - first
    }

    private func trendValue(_ scores: [Int]) -> String {
        let delta = trendDelta(scores)
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func trendIcon(_ scores: [Int]) -> String {
        let delta = trendDelta(scores)
        if delta > 2 { return "arrow.up.right" }
        if delta < -2 { return "arrow.down.right" }
        return "arrow.right"
    }

    private func trendColor(_ scores: [Int]) -> Color {
        let delta = trendDelta(scores)
        if delta > 2 { return KColor.success }
        if delta < -2 { return KColor.danger }
        return KColor.textSecondary
    }

    // MARK: Depth / range trend

    @ViewBuilder
    private var depthTrendCard: some View {
        let peaks = focusHistory.compactMap { $0.meanPeakAngle }
        let asymmetries = focusHistory.compactMap { $0.asymmetryDeg }

        if peaks.count > 1 {
            KCard {
                VStack(alignment: .leading, spacing: KSpacing.md) {
                    HStack {
                        Eyebrow(text: "Peak joint angle")
                        Spacer()
                        Text("Lower means deeper")
                            .font(.system(size: 11))
                            .foregroundStyle(KColor.textTertiary)
                    }
                    Sparkline(values: peaks, tint: KColor.teal)
                        .frame(height: 64)
                    HStack(spacing: KSpacing.sm) {
                        MetricChip(label: "First",
                                   value: "\(Int(peaks.first ?? 0))°",
                                   tint: KColor.textSecondary)
                        MetricChip(label: "Latest",
                                   value: "\(Int(peaks.last ?? 0))°",
                                   tint: KColor.textPrimary)
                        MetricChip(label: "Deepest",
                                   value: "\(Int(peaks.min() ?? 0))°",
                                   tint: KColor.teal)
                    }
                }
            }
        } else if asymmetries.count > 1 {
            KCard {
                VStack(alignment: .leading, spacing: KSpacing.md) {
                    Eyebrow(text: "Left / right difference")
                    Sparkline(values: asymmetries, tint: KColor.violet)
                        .frame(height: 64)
                    HStack(spacing: KSpacing.sm) {
                        MetricChip(label: "First",
                                   value: "\(Int(asymmetries.first ?? 0))°",
                                   tint: KColor.textSecondary)
                        MetricChip(label: "Latest",
                                   value: "\(Int(asymmetries.last ?? 0))°",
                                   tint: KColor.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: Activity

    private var activityCard: some View {
        let counts = sessionsPerDay(days: 14)
        let maxCount = max(counts.max() ?? 1, 1)
        return KCard {
            VStack(alignment: .leading, spacing: KSpacing.md) {
                HStack {
                    Eyebrow(text: "Activity")
                    Spacer()
                    Text("\(counts.reduce(0, +)) sessions in 14 days")
                        .font(.system(size: 11))
                        .foregroundStyle(KColor.textTertiary)
                }
                HStack(spacing: 6) {
                    ForEach(counts.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(counts[i] > 0 ? KColor.teal : KColor.separator.opacity(0.6))
                            .frame(height: counts[i] > 0
                                   ? max(12, 56 * CGFloat(counts[i]) / CGFloat(maxCount))
                                   : 10)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 60, alignment: .bottom)
                Text("Sessions logged over the last two weeks.")
                    .font(KFont.caption)
                    .foregroundStyle(KColor.textSecondary)
            }
        }
    }

    /// Session counts for the trailing `days` days, oldest bar on the left.
    private func sessionsPerDay(days: Int) -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            return records.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
        }
    }

    // MARK: Session list

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: KSpacing.sm) {
            SectionHeader("Recent analyses", eyebrow: "History") {
                Text("\(filteredRecords.count)")
                    .font(KFont.callout)
                    .foregroundStyle(KColor.textTertiary)
            }
            KCard(padding: KSpacing.sm) {
                VStack(spacing: 0) {
                    ForEach(filteredRecords) { record in
                        NavigationLink {
                            AnalysisRecordDetailView(record: record)
                        } label: {
                            AnalysisRecordRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                AnalysisLibrary.delete(record, from: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if record.id != filteredRecords.last?.id {
                            Divider().overlay(KColor.separator)
                        }
                    }
                }
            }
            Text("Videos stay on this device — currently using \(AnalysisStorage.formattedTotalSize).")
                .font(.system(size: 11))
                .foregroundStyle(KColor.textTertiary)
                .padding(.horizontal, KSpacing.xxs)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: KSpacing.lg) {
                KCard {
                    VStack(spacing: KSpacing.md) {
                        KEmptyState(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "No saved analyses yet",
                            message: "Every analysis you run is saved here automatically, so you can watch scores, depth, and tempo change across a training block."
                        )
                        Button {
                            router.goToWorkout(.savedVideo)
                        } label: {
                            Label("Analyze a movement", systemImage: "waveform.path.ecg")
                        }
                        .buttonStyle(KPrimaryButtonStyle())
                    }
                }
            }
            .padding(.horizontal, KSpacing.screenH)
            .padding(.top, KSpacing.md)
        }
    }

    @ViewBuilder
    private func notEnoughData(_ message: String) -> some View {
        HStack(alignment: .top, spacing: KSpacing.xs) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .foregroundStyle(KColor.textTertiary)
                .imageScale(.small)
                .padding(.top, 1)
            Text(message)
                .font(KFont.caption)
                .foregroundStyle(KColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - CSV export

    private enum ExportScope { case all, filtered, perRep }

    private func exportCSV(scope: ExportScope) {
        let result: Result<URL, Error>
        switch scope {
        case .all:
            result = CSVExporter.writeSessions(records, fileNameHint: "kinetriq-history")
        case .filtered:
            result = CSVExporter.writeSessions(
                filteredRecords,
                fileNameHint: "kinetriq-\(focusMovementName)"
            )
        case .perRep:
            result = CSVExporter.writeReps(filteredRecords, fileNameHint: "kinetriq-reps")
        }

        switch result {
        case .success(let url):
            sharePayload = SharePayload(items: [url])
        case .failure(let error):
            exportError = error.localizedDescription
        }
    }
}

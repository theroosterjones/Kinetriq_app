import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.kevinjones.Kinetriq", category: "AnalysisLibrary")

/// Owns the SwiftData stack and the few operations that touch it from outside a
/// SwiftUI `@Query`: saving a finished analysis, deleting one with its media, and
/// fetching history for trends, CSV export, and sync.
enum AnalysisLibrary {

    static let schema = Schema([AnalysisRecord.self])

    /// Builds the app's persistent container.
    ///
    /// Falls back to an in-memory store rather than trapping: a corrupt store would
    /// otherwise make the app unlaunchable, and losing history is a far better
    /// failure than losing the analysis pipeline.
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            )
        } catch {
            logger.error("Persistent store unavailable, falling back to memory: \(error.localizedDescription, privacy: .public)")
            // A forced try is acceptable here only because an in-memory container
            // with a valid schema has no failure mode left.
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }

    // MARK: - Writing

    @discardableResult
    @MainActor
    static func insert(_ record: AnalysisRecord, into context: ModelContext) -> Bool {
        context.insert(record)
        do {
            try context.save()
            // Local save is what matters; the upload is opportunistic and retries on
            // the next foreground if it fails, so it is deliberately not awaited.
            Task { await SyncService.shared.syncPending(context: context) }
            return true
        } catch {
            logger.error("Failed to save analysis record: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @MainActor
    static func delete(_ record: AnalysisRecord, from context: ModelContext) {
        AnalysisStorage.delete(fileName: record.videoFileName)
        AnalysisStorage.delete(fileName: record.thumbnailFileName)
        context.delete(record)
        try? context.save()
    }

    @MainActor
    static func deleteAll(from context: ModelContext) {
        for record in fetchAll(from: context) {
            AnalysisStorage.delete(fileName: record.videoFileName)
            AnalysisStorage.delete(fileName: record.thumbnailFileName)
            context.delete(record)
        }
        try? context.save()
    }

    // MARK: - Reading

    /// Every record, newest first.
    @MainActor
    static func fetchAll(from context: ModelContext) -> [AnalysisRecord] {
        let descriptor = FetchDescriptor<AnalysisRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// History for one movement, oldest first — the order trend analysis expects.
    @MainActor
    static func fetchHistory(
        movementKey: String,
        limit: Int? = nil,
        from context: ModelContext
    ) -> [AnalysisRecord] {
        var descriptor = FetchDescriptor<AnalysisRecord>(
            predicate: #Predicate { $0.movementKey == movementKey },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        return ((try? context.fetch(descriptor)) ?? []).reversed()
    }

    /// Whether this device has any saved analyses at all.
    ///
    /// Counted rather than fetched because restore asks this on every launch, and
    /// materializing a long history just to check for emptiness is wasteful.
    @MainActor
    static func isEmpty(in context: ModelContext) -> Bool {
        let count = try? context.fetchCount(FetchDescriptor<AnalysisRecord>())
        return (count ?? 0) == 0
    }

    /// Records whose metrics have not yet been accepted by the backend.
    @MainActor
    static func fetchUnsynced(from context: ModelContext) -> [AnalysisRecord] {
        let descriptor = FetchDescriptor<AnalysisRecord>(
            predicate: #Predicate { $0.syncedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

import Foundation

// MARK: - Faults

/// A technique problem Kinetriq can actually *measure*, as opposed to one a
/// generic exercise library would assert.
///
/// Every case here maps to a number the pipeline already produces. Nothing is
/// inferred from the exercise name alone, because a library that tells a lifter
/// about faults they may not have is noise — and after the first two visits, noise
/// nobody opens.
enum MovementFault: String, CaseIterable, Identifiable {
    /// Lowering phase of 1.0 s or faster — the collector's own control threshold.
    case rushedEccentric
    /// Peak angle scattered widely across reps.
    case inconsistentDepth
    /// Set sped up noticeably in its second half.
    case acceleratingTempo
    /// Shallower than this user's own best recorded range for the movement.
    case rangeBelowPersonalBest
    /// Assessment flagged a side-to-side difference.
    case asymmetry
    /// Not a technique fault — a filming problem that makes the rest unreliable.
    case lowTracking
    /// Too few reps for a consistency score to mean anything.
    case tooFewReps

    var id: String { rawValue }
}

// MARK: - Detection

/// Derives the faults present in one saved analysis.
///
/// Thresholds intentionally match the ones the scoring and coaching code already
/// uses, so a lesson never contradicts the score printed next to it.
enum TechniqueFaultDetector {

    /// Peak-angle spread at which `RepMetricsCollector` starts taking real points off.
    static let inconsistentDepthStdDev: Float = 8.0

    /// Fraction the second half of a set must speed up by before it is worth naming.
    static let accelerationThreshold = 0.25

    /// How much shallower than the user's own best before range is worth raising.
    static let rangeRegressionDegrees = 10.0

    /// Tracking below this makes every other number approximate.
    static let trackingFloor = 0.70

    /// - Parameter personalBestPeakAngle: the deepest mean peak angle this user has
    ///   recorded for this movement. Compared against rather than a population norm
    ///   — Kinetriq has no population data, and pretending otherwise would be a
    ///   claim it cannot support.
    static func faults(
        in record: AnalysisRecord,
        personalBestPeakAngle: Double? = nil
    ) -> [MovementFault] {
        var faults: [MovementFault] = []

        if record.poseDetectionRate < trackingFloor {
            faults.append(.lowTracking)
        }

        if record.kind == .assessment {
            if record.asymmetryFlag { faults.append(.asymmetry) }
            return faults
        }

        let reps = record.perRepMetrics

        if reps.count < 3 {
            faults.append(.tooFewReps)
            return faults
        }

        let fastCount = reps.filter(\.lacksEccentricControl).count
        if Double(fastCount) / Double(reps.count) >= 0.5 {
            faults.append(.rushedEccentric)
        }

        let peaks = reps.map(\.peakFlexionAngle).filter { $0.isFinite && $0 < 1000 }
        if peaks.count >= 3, standardDeviation(peaks) >= inconsistentDepthStdDev {
            faults.append(.inconsistentDepth)
        }

        if didAccelerate(reps) {
            faults.append(.acceleratingTempo)
        }

        if let best = personalBestPeakAngle,
           let current = record.meanPeakAngle,
           current - best >= rangeRegressionDegrees {
            faults.append(.rangeBelowPersonalBest)
        }

        return faults
    }

    /// Compares active time (eccentric + concentric) in the first half of the set
    /// against the second.
    private static func didAccelerate(_ reps: [RepMetric]) -> Bool {
        guard reps.count >= 4 else { return false }
        let mid = reps.count / 2

        func activeAverage(_ slice: ArraySlice<RepMetric>) -> Double {
            guard !slice.isEmpty else { return 0 }
            let total = slice.reduce(0.0) { $0 + $1.eccentricDuration + $1.concentricDuration }
            return total / Double(slice.count)
        }

        let early = activeAverage(reps.prefix(mid))
        let late = activeAverage(reps.suffix(reps.count - mid))
        guard early > 0.3 else { return false }
        return (late - early) / early <= -accelerationThreshold
    }

    private static func standardDeviation(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let n = Float(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return variance.squareRoot()
    }
}

// MARK: - Movement families

/// Coaching cues generalize by pattern, not by exercise name. A rushed eccentric in
/// a squat and in a lunge want the same correction; a rushed eccentric in a curl
/// does not.
enum MovementFamily: String {
    case squat
    case hinge
    case lunge
    case horizontalPull
    case verticalPull
    case press
    case dip
    case curl
    case assessment

    init(exerciseType: ExerciseType) {
        switch exerciseType {
        case .squat:                              self = .squat
        case .deadlift, .hipHingeSide, .hipHingeBack: self = .hinge
        case .lunge:                              self = .lunge
        case .row:                                self = .horizontalPull
        case .latPulldown, .latPulldownFront:     self = .verticalPull
        case .overheadPress:                      self = .press
        case .dips:                               self = .dip
        case .elbowCurl:                          self = .curl
        case .shoulderAssessment:                 self = .assessment
        }
    }

    init(record: AnalysisRecord) {
        if let exerciseType = record.exerciseType {
            self.init(exerciseType: exerciseType)
        } else {
            self = .assessment
        }
    }

    /// The word to use for the lengthened end of the movement in cue text.
    var bottomWord: String {
        switch self {
        case .squat, .lunge:                  return "the bottom"
        case .hinge:                          return "the stretch"
        case .horizontalPull, .verticalPull:  return "the hang"
        case .press, .dip:                    return "the bottom"
        case .curl:                           return "full extension"
        case .assessment:                     return "the end range"
        }
    }
}

// MARK: - Lessons

/// One piece of technique instruction, surfaced because a measurement asked for it.
struct TechniqueLesson: Identifiable, Equatable {
    let id: String
    let fault: MovementFault
    let title: String
    /// Why this matters, in one sentence, tied to what was measured.
    let why: String
    let cues: [String]
    let drill: String?

    /// Name of a bundled illustration asset, when one exists for this lesson.
    ///
    /// Always `nil` today: **Kinetriq ships these lessons as text.** The obvious
    /// source, Everkinetic, is CC BY-SA 4.0, and share-alike would cover any
    /// recolouring, cropping, or overlay — so the art could only ship pixel-for-pixel
    /// unmodified. The plumbing and the attribution field stay so that commissioned
    /// or properly licensed art is a content change rather than an engineering one.
    /// Rationale and the routes that would unblock images: `docs/ContentLibrary.md`.
    let illustrationAsset: String?
    let attribution: String?

    init(
        id: String,
        fault: MovementFault,
        title: String,
        why: String,
        cues: [String],
        drill: String? = nil,
        illustrationAsset: String? = nil,
        attribution: String? = nil
    ) {
        self.id = id
        self.fault = fault
        self.title = title
        self.why = why
        self.cues = cues
        self.drill = drill
        self.illustrationAsset = illustrationAsset
        self.attribution = attribution
    }
}

/// Fault-triggered technique instruction.
///
/// The difference between this and a browsable exercise encyclopedia is that
/// nothing here appears unless the user's own set produced the number behind it.
/// Generic libraries get opened twice; a lesson that starts "your eccentric was
/// 0.8 seconds" is about the set that just happened.
enum TechniqueLibrary {

    /// At most this many lessons after a set. Three corrections is already more than
    /// anyone acts on.
    static let maximumLessons = 2

    /// Lessons for one analysis.
    ///
    /// - Parameter history: prior samples for the same movement, used only to
    ///   establish the user's own best range.
    static func lessons(for record: AnalysisRecord, history: [TrendSample] = []) -> [TechniqueLesson] {
        let personalBest = history
            .compactMap(\.meanPeakAngle)
            .min()

        let faults = TechniqueFaultDetector.faults(in: record, personalBestPeakAngle: personalBest)
        let family = MovementFamily(record: record)

        return faults
            .compactMap { lesson(for: $0, family: family) }
            .prefix(maximumLessons)
            .map { $0 }
    }

    /// All the faults Kinetriq can detect for a movement family, for the browsable
    /// library. Presented as "what Kinetriq measures here", not as advice.
    static func catalog(for family: MovementFamily) -> [TechniqueLesson] {
        MovementFault.allCases.compactMap { lesson(for: $0, family: family) }
    }

    // MARK: - Content

    static func lesson(for fault: MovementFault, family: MovementFamily) -> TechniqueLesson? {
        switch fault {
        case .rushedEccentric:      return rushedEccentric(family)
        case .inconsistentDepth:    return inconsistentDepth(family)
        case .acceleratingTempo:    return acceleratingTempo(family)
        case .rangeBelowPersonalBest: return rangeRegression(family)
        case .asymmetry:            return asymmetry(family)
        case .lowTracking:          return lowTracking(family)
        case .tooFewReps:           return tooFewReps(family)
        }
    }

    private static func rushedEccentric(_ family: MovementFamily) -> TechniqueLesson {
        let cues: [String]
        let drill: String

        switch family {
        case .squat, .lunge:
            cues = [
                "Count three seconds down, every rep — out loud if you have to.",
                "Sit back into the hips rather than dropping straight down.",
                "Keep tension through the whole descent instead of relaxing and catching yourself at \(family.bottomWord)."
            ]
            drill = "Do one set at half your usual load with a 4-second descent. That is the tempo you are aiming to keep when the weight goes back up."
        case .hinge:
            cues = [
                "Push the hips back slowly; the bar or your hands should track close to the legs the whole way.",
                "Feel the hamstrings lengthen on the way down rather than letting the weight fall.",
                "Stop the descent where your back position changes, not where the weight runs out of room."
            ]
            drill = "Romanian deadlifts at 40% load with a 4-second lower. Stop each rep the moment your lower back rounds."
        case .horizontalPull, .verticalPull:
            cues = [
                "Let the weight pull your arms out slowly — do not just release the squeeze.",
                "Control the shoulder blade all the way back to \(family.bottomWord).",
                "Three seconds out is the target; two is the minimum."
            ]
            drill = "One set where the lowering phase takes twice as long as the pull. Drop the weight until that is possible."
        case .press, .dip:
            cues = [
                "Lower under control rather than letting the elbows collapse.",
                "Keep the shoulder blades set the whole way down.",
                "Reach \(family.bottomWord) deliberately, then press."
            ]
            drill = "Half-load set with a 4-second descent and a one-second pause at the bottom."
        case .curl:
            cues = [
                "The lowering half of a curl is where the size comes from — do not give it away.",
                "Take three seconds to reach full extension.",
                "Keep the elbow still; if it drifts forward, the weight is too heavy to control."
            ]
            drill = "Drop the load 30% and take four seconds to lower every rep for one set."
        case .assessment:
            cues = ["Move through the range slowly so the measurement reflects control rather than momentum."]
            drill = "Repeat the assessment taking at least three seconds in each direction."
        }

        return TechniqueLesson(
            id: "rushed-eccentric-\(family.rawValue)",
            fault: .rushedEccentric,
            title: "Slow the lowering phase",
            why: "Kinetriq measured an eccentric of a second or less on most of these reps. That is fast enough that gravity, not you, is doing the lowering — and it is where most of the training effect and most of the joint protection lives.",
            cues: cues,
            drill: drill
        )
    }

    private static func inconsistentDepth(_ family: MovementFamily) -> TechniqueLesson {
        let cues: [String]
        switch family {
        case .squat, .lunge:
            cues = [
                "Pick a depth you can hit every rep, not the depth of your best rep.",
                "Set a physical target — a box, a bench, a mark on the wall behind you.",
                "If the last reps are getting shallower, the set is longer than your control allows."
            ]
        case .hinge:
            cues = [
                "Stop every rep at the same point in the hamstring stretch.",
                "Use a consistent bar path; drifting forward changes the measured angle.",
                "Film from the same position each time so depth is comparable."
            ]
        case .horizontalPull, .verticalPull:
            cues = [
                "Pull to the same contact point every rep — sternum, chin, or a fixed spot.",
                "Return all the way to \(family.bottomWord) each time rather than cutting the return short.",
                "Reps that shorten as the set goes on are fatigue, not a strength gain."
            ]
        case .press, .dip:
            cues = [
                "Descend to the same depth every rep rather than to failure depth.",
                "Lock out fully at the top so both ends of the range stay constant.",
                "Shortening the range as you fatigue makes the set look easier than it was."
            ]
        case .curl:
            cues = [
                "Reach the same extension every rep — partial reps at the bottom are the usual culprit.",
                "Keep the elbow in the same place so the measured angle is comparable.",
                "Stop the set when the range starts shrinking."
            ]
        case .assessment:
            cues = ["Repeat the assessment with the same setup and pace so the two measurements are comparable."]
        }

        return TechniqueLesson(
            id: "inconsistent-depth-\(family.rawValue)",
            fault: .inconsistentDepth,
            title: "Make every rep the same depth",
            why: "Peak angle varied noticeably from rep to rep in this set. That variation is most of what drags a consistency score down, and it usually means the last few reps are quietly shorter than the first few.",
            cues: cues,
            drill: "Set a physical depth marker and do one set where every rep touches it. Reps that cannot reach it end the set."
        )
    }

    private static func acceleratingTempo(_ family: MovementFamily) -> TechniqueLesson {
        TechniqueLesson(
            id: "accelerating-tempo-\(family.rawValue)",
            fault: .acceleratingTempo,
            title: "You sped up as the set went on",
            why: "The second half of this set moved noticeably faster than the first. Speeding up under fatigue usually means bouncing out of \(family.bottomWord) rather than lifting out of it, which quietly removes the hardest part of the rep.",
            cues: [
                "Hold the same count on every rep, including the last one.",
                "A brief pause at \(family.bottomWord) kills the bounce and makes the range honest.",
                "If the pace only holds for the first half, the set is one or two reps too long."
            ],
            drill: "Add a one-second pause at \(family.bottomWord) of every rep for one set. It will feel much harder at the same load — that is the part you were skipping."
        )
    }

    private static func rangeRegression(_ family: MovementFamily) -> TechniqueLesson {
        TechniqueLesson(
            id: "range-regression-\(family.rawValue)",
            fault: .rangeBelowPersonalBest,
            title: "Shallower than your own best",
            why: "This set's range was meaningfully shorter than the deepest you have recorded for this movement. That is often a deliberate trade for load, but it is worth knowing you made it rather than discovering it a month later.",
            cues: [
                "If the load went up, the shorter range is probably the reason.",
                "If the load did not change, check mobility, warm-up, or fatigue before adding weight.",
                "Filming from a different angle can also shorten the measured range — match your previous camera position before concluding anything."
            ],
            drill: "Run one set at your previous working load and compare the range. If it comes back, this was load. If it does not, it is mobility or fatigue."
        )
    }

    private static func asymmetry(_ family: MovementFamily) -> TechniqueLesson {
        TechniqueLesson(
            id: "asymmetry-\(family.rawValue)",
            fault: .asymmetry,
            title: "One side is moving further than the other",
            why: "This assessment measured a side-to-side difference large enough to flag. A difference in range is not an injury and not a diagnosis — but loading a pattern heavily on top of one tends to make it more pronounced, not less.",
            cues: [
                "Train the restricted side first and match the stronger side to it, not the other way round.",
                "Single-side work for a few weeks tells you more than another bilateral assessment will.",
                "Re-assess with the same camera setup — a rotated camera can manufacture an asymmetry that is not there."
            ],
            drill: "Repeat the assessment filmed from the opposite side. A real difference shows up both ways; a camera artefact flips."
        )
    }

    private static func lowTracking(_ family: MovementFamily) -> TechniqueLesson {
        TechniqueLesson(
            id: "low-tracking-\(family.rawValue)",
            fault: .lowTracking,
            title: "Fix the framing before trusting these numbers",
            why: "Pose was tracked in fewer than 70% of the frames, so the angles, reps, and score above are approximate. This is a filming problem, not a technique one, and it is worth fixing first because everything else depends on it.",
            cues: [
                "Get your whole body in frame from head to feet for the entire set.",
                "Light from the front; a bright window behind you turns you into a silhouette.",
                "Only one person in frame — Kinetriq tracks a single body and will jump between people.",
                "Keep equipment from covering the joint being measured."
            ],
            drill: "Refilm one set with the phone further back and the light in front of you, then compare the tracking percentage."
        )
    }

    private static func tooFewReps(_ family: MovementFamily) -> TechniqueLesson {
        TechniqueLesson(
            id: "too-few-reps-\(family.rawValue)",
            fault: .tooFewReps,
            title: "Record at least three reps",
            why: "A consistency score compares reps against each other, so it needs at least three to mean anything. With fewer, Kinetriq can still show angles and tempo but cannot tell you whether the movement was repeatable.",
            cues: [
                "Three reps is the minimum; five or more gives a much steadier read.",
                "Start filming before the first rep and stop after the last one settles.",
                "Partial reps at the start of a set often fail to register — begin from a full starting position."
            ],
            drill: nil
        )
    }
}

import Foundation
import simd

enum CustomOverlayOption: String, CaseIterable, Identifiable {
    case centerFoot = "Center Foot"
    case forearmAlignment = "Forearm Alignment"
    case lowerLegAlignment = "Lower Leg Alignment"
    case backAlignment = "Back Alignment"

    var id: String { rawValue }
}

enum CustomOverlayBuilder {

    static func instructions(
        options: Set<CustomOverlayOption>,
        landmarks: PoseResult,
        side: BodySide,
        exerciseType: ExerciseType? = nil,
        state: CustomOverlayState? = nil
    ) -> [OverlayInstruction] {
        guard !options.isEmpty else { return [] }

        var instructions: [OverlayInstruction] = []
        if options.contains(.centerFoot) {
            if let instruction = state?.centerFootInstruction(landmarks: landmarks, side: side) {
                instructions.append(instruction)
            } else if let footCenter = centerFootPosition(landmarks: landmarks, side: side) {
                let verticalAnchor = roomVerticalAnchor(through: footCenter, landmarks: landmarks, side: side)
                instructions.append(.extendedLine(from: verticalAnchor, through: footCenter, color: .magenta, width: 2))
            }
        }

        if options.contains(.forearmAlignment) {
            if let instruction = state?.forearmInstruction(landmarks: landmarks, side: side) {
                instructions.append(instruction)
            } else if let wrist = landmarks.position(for: .wrist(side)),
                      let elbow = landmarks.position(for: .elbow(side)) {
                instructions.append(.extendedLine(from: wrist, through: elbow, color: .cyan, width: 2))
            }
        }

        if options.contains(.lowerLegAlignment) {
            if let instruction = state?.lowerLegInstruction(landmarks: landmarks, side: side) {
                instructions.append(instruction)
            } else if let ankle = landmarks.position(for: .ankle(side)),
                      let knee = landmarks.position(for: .knee(side)) {
                instructions.append(.extendedLine(from: ankle, through: knee, color: .cyan, width: 2))
            }
        }

        if options.contains(.backAlignment) {
            if let instruction = state?.backInstruction(
                landmarks: landmarks,
                side: side,
                exerciseType: exerciseType
            ) {
                instructions.append(instruction)
            } else if usesFrontalBackAlignment(exerciseType: exerciseType),
                      let line = frontalSpineLine(landmarks: landmarks) {
                instructions.append(.extendedLine(from: line.hip, through: line.shoulder, color: .cyan, width: 2))
            } else if let hip = landmarks.position(for: .hip(side)),
                      let shoulder = landmarks.position(for: .shoulder(side)) {
                instructions.append(.extendedLine(from: hip, through: shoulder, color: .cyan, width: 2))
            }
        }

        return instructions
    }

    fileprivate static func centerFootPosition(landmarks: PoseResult, side: BodySide) -> SIMD2<Float>? {
        let heel = landmarks.position(for: .heel(side))
        let toe = landmarks.position(for: .footIndex(side))
        if let heel, let toe {
            return (heel + toe) / 2.0
        }
        return toe ?? heel ?? landmarks.position(for: .ankle(side))
    }

    fileprivate static func roomVerticalDirection(landmarks: PoseResult, side: BodySide) -> SIMD2<Float> {
        guard let hip = landmarks.position(for: .hip(side)),
              let shoulder = landmarks.position(for: .shoulder(side)) else {
            return SIMD2(0, -1)
        }

        let vertical = shoulder - hip
        guard simd_length_squared(vertical) > 1e-6 else {
            return SIMD2(0, -1)
        }

        return simd_normalize(vertical)
    }

    fileprivate static func roomVerticalAnchor(
        through point: SIMD2<Float>,
        landmarks: PoseResult,
        side: BodySide
    ) -> SIMD2<Float> {
        point - roomVerticalDirection(landmarks: landmarks, side: side) * 0.1
    }

    fileprivate static func usesFrontalBackAlignment(exerciseType: ExerciseType?) -> Bool {
        switch exerciseType {
        case .hipHingeBack, .latPulldownFront, .overheadPress:
            return true
        default:
            return false
        }
    }

    fileprivate static func frontalSpineLine(landmarks: PoseResult) -> (hip: SIMD2<Float>, shoulder: SIMD2<Float>)? {
        guard let leftHip = landmarks.position(for: .hip(.left)),
              let rightHip = landmarks.position(for: .hip(.right)),
              let leftShoulder = landmarks.position(for: .shoulder(.left)),
              let rightShoulder = landmarks.position(for: .shoulder(.right)) else {
            return nil
        }

        return (
            hip: (leftHip + rightHip) / 2.0,
            shoulder: (leftShoulder + rightShoulder) / 2.0
        )
    }
}

final class CustomOverlayState {
    private var centerFootTrackers: [BodySide: CenterFootTracker] = [:]
    private let smoother = LandmarkSmoother()

    /// Same 2D spike caps as the side-view analyzers. One-frame MediaPipe snaps
    /// cannot yank an extended alignment line.
    private let legMaxSpeed2D: Float = 2.5
    private let armMaxSpeed2D: Float = 3.0

    func reset() {
        centerFootTrackers.removeAll()
        smoother.reset()
    }

    func centerFootInstruction(landmarks: PoseResult, side: BodySide) -> OverlayInstruction? {
        var tracker = centerFootTrackers[side] ?? CenterFootTracker()
        defer { centerFootTrackers[side] = tracker }

        guard let rawPoint = CustomOverlayBuilder.centerFootPosition(landmarks: landmarks, side: side) else {
            return tracker.lockedInstruction()
        }

        let ts = landmarks.timestamp
        let point = smoother.stabilizeAnchor(
            key: "\(side)_overlay_foot_anchor",
            position: rawPoint
        )
        let direction = smoothedTorsoDirection(landmarks: landmarks, side: side, timestamp: ts)
        guard let line = tracker.update(point: point, direction: direction) else { return nil }
        return .extendedLine(from: line.from, through: line.through, color: .magenta, width: 2)
    }

    func forearmInstruction(landmarks: PoseResult, side: BodySide) -> OverlayInstruction? {
        guard let rawWrist = landmarks.position(for: .wrist(side)),
              let rawElbow = landmarks.position(for: .elbow(side)) else {
            return nil
        }

        let ts = landmarks.timestamp
        let wrist = smoother.smooth(
            key: "\(side)_overlay_wrist",
            position: rawWrist,
            timestamp: ts,
            maxSpeed: armMaxSpeed2D
        )
        let elbow = smoother.smooth(
            key: "\(side)_overlay_elbow",
            position: rawElbow,
            timestamp: ts,
            maxSpeed: armMaxSpeed2D
        )
        return .extendedLine(from: wrist, through: elbow, color: .cyan, width: 2)
    }

    /// Planted ankle + spike-rejected knee so the infinite shin line stays
    /// accurate through the squat without flickering when MediaPipe snaps.
    func lowerLegInstruction(landmarks: PoseResult, side: BodySide) -> OverlayInstruction? {
        guard let rawAnkle = landmarks.position(for: .ankle(side)),
              let rawKnee = landmarks.position(for: .knee(side)) else {
            return nil
        }

        let ts = landmarks.timestamp
        let ankle = smoother.stabilizeAnchor(
            key: "\(side)_overlay_ankle_anchor",
            position: rawAnkle
        )
        let knee = smoother.smooth(
            key: "\(side)_overlay_knee",
            position: rawKnee,
            timestamp: ts,
            maxSpeed: legMaxSpeed2D
        )

        return .extendedLine(from: ankle, through: knee, color: .cyan, width: 2)
    }

    func backInstruction(
        landmarks: PoseResult,
        side: BodySide,
        exerciseType: ExerciseType?
    ) -> OverlayInstruction? {
        let ts = landmarks.timestamp
        if CustomOverlayBuilder.usesFrontalBackAlignment(exerciseType: exerciseType) {
            guard let leftHip = landmarks.position(for: .hip(.left)),
                  let rightHip = landmarks.position(for: .hip(.right)),
                  let leftShoulder = landmarks.position(for: .shoulder(.left)),
                  let rightShoulder = landmarks.position(for: .shoulder(.right)) else {
                return nil
            }
            let hip = (
                smoother.smooth(key: "overlay_front_hip_l", position: leftHip, timestamp: ts, maxSpeed: legMaxSpeed2D)
                + smoother.smooth(key: "overlay_front_hip_r", position: rightHip, timestamp: ts, maxSpeed: legMaxSpeed2D)
            ) / 2
            let shoulder = (
                smoother.smooth(key: "overlay_front_shoulder_l", position: leftShoulder, timestamp: ts, maxSpeed: legMaxSpeed2D)
                + smoother.smooth(key: "overlay_front_shoulder_r", position: rightShoulder, timestamp: ts, maxSpeed: legMaxSpeed2D)
            ) / 2
            return .extendedLine(from: hip, through: shoulder, color: .cyan, width: 2)
        }

        guard let rawHip = landmarks.position(for: .hip(side)),
              let rawShoulder = landmarks.position(for: .shoulder(side)) else {
            return nil
        }
        let hip = smoother.smooth(
            key: "\(side)_overlay_back_hip",
            position: rawHip,
            timestamp: ts,
            maxSpeed: legMaxSpeed2D
        )
        let shoulder = smoother.smooth(
            key: "\(side)_overlay_back_shoulder",
            position: rawShoulder,
            timestamp: ts,
            maxSpeed: legMaxSpeed2D
        )
        return .extendedLine(from: hip, through: shoulder, color: .cyan, width: 2)
    }

    private func smoothedTorsoDirection(
        landmarks: PoseResult,
        side: BodySide,
        timestamp: Double
    ) -> SIMD2<Float> {
        guard let rawHip = landmarks.position(for: .hip(side)),
              let rawShoulder = landmarks.position(for: .shoulder(side)) else {
            return SIMD2(0, -1)
        }
        let hip = smoother.smooth(
            key: "\(side)_overlay_torso_hip",
            position: rawHip,
            timestamp: timestamp,
            maxSpeed: legMaxSpeed2D
        )
        let shoulder = smoother.smooth(
            key: "\(side)_overlay_torso_shoulder",
            position: rawShoulder,
            timestamp: timestamp,
            maxSpeed: legMaxSpeed2D
        )
        let vertical = shoulder - hip
        guard simd_length_squared(vertical) > 1e-6 else {
            return SIMD2(0, -1)
        }
        return simd_normalize(vertical)
    }
}

private struct CenterFootTracker {
    private struct Sample {
        let point: SIMD2<Float>
        let direction: SIMD2<Float>
    }

    private let requiredStableSamples = 6
    private let maxSampleWindow = 12
    private let stableRadius: Float = 0.025
    private let relocateRadius: Float = 0.08
    private let requiredRelocateFrames = 8

    private var samples: [Sample] = []
    private var lockedPoint: SIMD2<Float>?
    private var lockedDirection: SIMD2<Float>?
    private var relocateFrames = 0

    func lockedInstruction() -> OverlayInstruction? {
        guard let line = lockedLine() else { return nil }
        return .extendedLine(from: line.from, through: line.through, color: .magenta, width: 2)
    }

    mutating func update(point: SIMD2<Float>, direction: SIMD2<Float>) -> (from: SIMD2<Float>, through: SIMD2<Float>)? {
        if let lockedPoint, let lockedDirection {
            if simd_distance(point, lockedPoint) > relocateRadius {
                relocateFrames += 1
                if relocateFrames >= requiredRelocateFrames {
                    unlock()
                    addSample(point: point, direction: direction)
                    return averagedLine()
                }
            } else {
                relocateFrames = 0
            }
            return line(point: lockedPoint, direction: lockedDirection)
        }

        addSample(point: point, direction: direction)
        if let stable = stableLock() {
            lockedPoint = stable.point
            lockedDirection = stable.direction
            relocateFrames = 0
            return line(point: stable.point, direction: stable.direction)
        }

        return averagedLine()
    }

    private mutating func addSample(point: SIMD2<Float>, direction: SIMD2<Float>) {
        samples.append(Sample(point: point, direction: direction))
        if samples.count > maxSampleWindow {
            samples.removeFirst(samples.count - maxSampleWindow)
        }
    }

    private mutating func unlock() {
        samples.removeAll()
        lockedPoint = nil
        lockedDirection = nil
        relocateFrames = 0
    }

    private func stableLock() -> Sample? {
        guard samples.count >= requiredStableSamples else { return nil }

        let average = averageSample()
        let maxDistance = samples
            .map { simd_distance($0.point, average.point) }
            .max() ?? 0

        guard maxDistance <= stableRadius else { return nil }
        return average
    }

    private func averagedLine() -> (from: SIMD2<Float>, through: SIMD2<Float>)? {
        guard !samples.isEmpty else { return nil }
        let average = averageSample()
        return line(point: average.point, direction: average.direction)
    }

    private func lockedLine() -> (from: SIMD2<Float>, through: SIMD2<Float>)? {
        guard let lockedPoint, let lockedDirection else { return nil }
        return line(point: lockedPoint, direction: lockedDirection)
    }

    private func line(point: SIMD2<Float>, direction: SIMD2<Float>) -> (from: SIMD2<Float>, through: SIMD2<Float>) {
        (from: point - direction * 0.1, through: point)
    }

    private func averageSample() -> Sample {
        let total = samples.reduce(Sample(point: .zero, direction: .zero)) { partial, sample in
            Sample(
                point: partial.point + sample.point,
                direction: partial.direction + sample.direction
            )
        }
        let count = Float(samples.count)
        let averageDirection = total.direction / count
        let direction = simd_length_squared(averageDirection) > 1e-6
            ? simd_normalize(averageDirection)
            : SIMD2<Float>(0, -1)

        return Sample(point: total.point / count, direction: direction)
    }
}

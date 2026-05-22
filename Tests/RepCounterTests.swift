import XCTest
@testable import Kinetriq

final class RepCounterTests: XCTestCase {

    func testRepCounting() {
        let counter = RepCounter(extendedThreshold: 150, flexedThreshold: 100)

        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(counter.state, .extended)

        // Simulate lowering (angle decreasing)
        counter.update(angle: 140)
        XCTAssertEqual(counter.count, 0)
        counter.update(angle: 120)
        XCTAssertEqual(counter.count, 0)
        counter.update(angle: 95)  // below flexed threshold
        XCTAssertEqual(counter.state, .flexed)
        XCTAssertEqual(counter.count, 0)

        // Simulate rising (angle increasing)
        counter.update(angle: 130)
        XCTAssertEqual(counter.count, 0)
        counter.update(angle: 155)  // above extended threshold
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(counter.state, .extended)

        // Second rep
        counter.update(angle: 90)
        counter.update(angle: 160)
        XCTAssertEqual(counter.count, 2)
    }

    func testReset() {
        let counter = RepCounter(extendedThreshold: 150, flexedThreshold: 100)
        counter.update(angle: 90)
        counter.update(angle: 160)
        XCTAssertEqual(counter.count, 1)

        counter.reset()
        XCTAssertEqual(counter.count, 0)
        XCTAssertEqual(counter.state, .extended)
    }
}

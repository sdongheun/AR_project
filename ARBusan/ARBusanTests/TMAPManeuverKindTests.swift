import XCTest
@testable import ARBusan

final class TMAPManeuverKindTests: XCTestCase {
    func testTurnTypeMapping() {
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 11), .straight)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 12), .turnLeft)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 13), .turnRight)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 14), .uTurn)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 16), .turnLeft)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 17), .slightLeft)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 18), .slightRight)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 19), .turnRight)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 125), .overpass)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 126), .underpass)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 127), .stairs)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 200), .depart)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 201), .arrive)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 211), .crosswalk)
        XCTAssertEqual(TMAPManeuverKind.from(turnType: 999), .other)
    }

    func testTurnDirectionAndIsTurn() {
        XCTAssertEqual(TMAPManeuverKind.turnLeft.turnDirection, .left)
        XCTAssertEqual(TMAPManeuverKind.slightLeft.turnDirection, .left)
        XCTAssertEqual(TMAPManeuverKind.turnRight.turnDirection, .right)
        XCTAssertEqual(TMAPManeuverKind.slightRight.turnDirection, .right)
        XCTAssertEqual(TMAPManeuverKind.uTurn.turnDirection, .left)

        XCTAssertTrue(TMAPManeuverKind.turnLeft.isTurn)
        XCTAssertTrue(TMAPManeuverKind.slightRight.isTurn)
        XCTAssertFalse(TMAPManeuverKind.straight.isTurn)
        XCTAssertFalse(TMAPManeuverKind.crosswalk.isTurn)
        XCTAssertNil(TMAPManeuverKind.straight.turnDirection)
    }
}

import XCTest
@testable import PoteAgenda

final class OutingPastAndDiscussionTests: XCTestCase {
    private func makeOuting(
        startsAt: Date = Date(),
        endsAt: Date = Date(),
        cancelledAt: String? = nil,
        messageRetentionDays: Int = 7
    ) -> Outing {
        Outing(
            id: "outing-1",
            creatorId: "creator-1",
            groupId: nil,
            title: "Sortie",
            startsAt: DateHelpers.iso(startsAt),
            endsAt: DateHelpers.iso(endsAt),
            location: nil,
            note: nil,
            cancelledAt: cancelledAt,
            confirmedAt: nil,
            messageRetentionDays: messageRetentionDays
        )
    }

    // MARK: - isOutingPast (archivage des invitations)

    func testFutureOutingIsNotPast() {
        let outing = makeOuting(startsAt: Date().addingTimeInterval(3600), endsAt: Date().addingTimeInterval(7200))
        XCTAssertFalse(isOutingPast(outing))
    }

    func testOutingThatEndedIsPast() {
        let outing = makeOuting(startsAt: Date().addingTimeInterval(-7200), endsAt: Date().addingTimeInterval(-3600))
        XCTAssertTrue(isOutingPast(outing))
    }

    func testOngoingOutingIsNotYetPast() {
        // A commencé mais pas encore fini : ne doit pas être archivé prématurément.
        let outing = makeOuting(startsAt: Date().addingTimeInterval(-1800), endsAt: Date().addingTimeInterval(1800))
        XCTAssertFalse(isOutingPast(outing))
    }

    func testUnparsableEndDateIsTreatedAsNotPast() {
        var outing = makeOuting()
        outing = Outing(
            id: outing.id,
            creatorId: outing.creatorId,
            groupId: outing.groupId,
            title: outing.title,
            startsAt: outing.startsAt,
            endsAt: "not-a-date",
            location: outing.location,
            note: outing.note,
            cancelledAt: outing.cancelledAt,
            confirmedAt: outing.confirmedAt,
            messageRetentionDays: outing.messageRetentionDays
        )
        XCTAssertFalse(isOutingPast(outing))
    }

    // MARK: - canDiscussOuting (fenêtre de discussion après la sortie)

    func testCancelledOutingCannotBeDiscussed() {
        let outing = makeOuting(
            startsAt: Date().addingTimeInterval(-3600),
            endsAt: Date().addingTimeInterval(-1800),
            cancelledAt: DateHelpers.iso(Date())
        )
        XCTAssertFalse(canDiscussOuting(outing))
    }

    func testOutingWithinRetentionWindowCanBeDiscussed() {
        let outing = makeOuting(
            startsAt: Date().addingTimeInterval(-2 * 86_400),
            endsAt: Date().addingTimeInterval(-1 * 86_400),
            messageRetentionDays: 7
        )
        XCTAssertTrue(canDiscussOuting(outing))
    }

    func testOutingPastRetentionWindowCannotBeDiscussed() {
        let outing = makeOuting(
            startsAt: Date().addingTimeInterval(-10 * 86_400),
            endsAt: Date().addingTimeInterval(-9 * 86_400),
            messageRetentionDays: 7
        )
        XCTAssertFalse(canDiscussOuting(outing))
    }

    func testUpcomingOutingCanAlwaysBeDiscussed() {
        let outing = makeOuting(
            startsAt: Date().addingTimeInterval(3600),
            endsAt: Date().addingTimeInterval(7200),
            messageRetentionDays: 7
        )
        XCTAssertTrue(canDiscussOuting(outing))
    }
}

final class OutingResponseCasesTests: XCTestCase {
    func testResponseDecodesFromRawValues() throws {
        XCTAssertEqual(try decodeResponse("\"pending\""), .pending)
        XCTAssertEqual(try decodeResponse("\"accepted\""), .accepted)
        XCTAssertEqual(try decodeResponse("\"declined\""), .declined)
    }

    private func decodeResponse(_ json: String) throws -> OutingResponse {
        try JSONDecoder().decode(OutingResponse.self, from: Data(json.utf8))
    }
}

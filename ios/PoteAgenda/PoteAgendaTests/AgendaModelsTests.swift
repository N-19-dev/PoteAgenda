import SwiftUI
import XCTest
@testable import PoteAgenda

final class AgendaBlockTests: XCTestCase {
    private func makeBlock(
        startAt: String = "2026-03-05T18:00:00Z",
        endAt: String = "2026-03-05T19:00:00Z",
        style: AgendaBlockStyle = .outing
    ) -> AgendaBlock {
        AgendaBlock(
            id: "block-1",
            title: "Titre",
            subtitle: "Sous-titre",
            startAt: startAt,
            endAt: endAt,
            color: "#6366f1",
            ownEvent: nil,
            style: style,
            details: .generic
        )
    }

    func testTimeLabelSeparatesStartAndEnd() {
        let block = makeBlock()
        XCTAssertTrue(block.timeLabel.contains(" - "))
    }

    func testTimeLabelEmptyWhenDatesUnparsable() {
        let block = makeBlock(startAt: "not-a-date", endAt: "also-not-a-date")
        XCTAssertEqual(block.timeLabel, "")
    }

    func testDateRangeLabelSameDayUsesSingleDateFormat() {
        // Même jour : "date, heure - heure", pas de préfixe "Du ... au ...".
        let block = makeBlock(startAt: "2026-03-05T18:00:00Z", endAt: "2026-03-05T19:00:00Z")
        XCTAssertFalse(block.dateRangeLabel.hasPrefix("Du "))
        XCTAssertTrue(block.dateRangeLabel.contains(" - "))
    }

    func testDateRangeLabelMultiDayUsesRangeFormat() {
        // Événement multi-jours : préfixe "Du ... au ...".
        let block = makeBlock(startAt: "2026-03-05T22:00:00Z", endAt: "2026-03-07T01:00:00Z")
        XCTAssertTrue(block.dateRangeLabel.hasPrefix("Du "))
        XCTAssertTrue(block.dateRangeLabel.contains(" au "))
    }

    func testInitFromCalendarEventWithoutIdReturnsNil() {
        let event = CalendarEvent(id: nil, userId: "u1", title: "T", startAt: "2026-03-05T18:00:00Z", endAt: "2026-03-05T19:00:00Z", color: "#000000", source: "manual")
        XCTAssertNil(AgendaBlock(event: event))
    }

    func testInitFromCalendarEventUsesOwnBusyStyle() {
        let event = CalendarEvent(id: "evt-1", userId: "u1", title: "T", startAt: "2026-03-05T18:00:00Z", endAt: "2026-03-05T19:00:00Z", color: "#000000", source: "manual")
        let block = AgendaBlock(event: event)
        XCTAssertEqual(block?.style, .ownBusy)
        XCTAssertEqual(block?.id, "evt-1")
    }

    func testOverlapPriorityViaZIndexOrdersOwnBusyAboveFriendStyles() {
        // ownBusy doit primer visuellement sur les indispos/amis (zIndex plus élevé).
        XCTAssertGreaterThan(AgendaBlockStyle.friendBusy.zIndex, AgendaBlockStyle.ownBusy.zIndex)
        XCTAssertGreaterThan(AgendaBlockStyle.friendPending.zIndex, AgendaBlockStyle.ownBusy.zIndex)
        XCTAssertGreaterThan(AgendaBlockStyle.ownBusy.zIndex, AgendaBlockStyle.outing.zIndex)
    }

    func testFriendStylesUseSharedOverlayColors() {
        let block = makeBlock(style: .friendBusy)
        XCTAssertEqual(AgendaBlockStyle.friendBusy.backgroundColor(for: block), Color.poteBusyOther)

        let pendingBlock = makeBlock(style: .friendPending)
        XCTAssertEqual(AgendaBlockStyle.friendPending.backgroundColor(for: pendingBlock), Color.potePendingOther)
    }

    func testOwnAndOutingStylesUseBlockColor() {
        let block = makeBlock(style: .outing)
        XCTAssertEqual(AgendaBlockStyle.outing.backgroundColor(for: block), Color(hex: "#6366f1"))
    }
}

final class OutingResponseAgendaMappingTests: XCTestCase {
    func testEachResponseHasADistinctLabel() {
        let labels = Set([OutingResponse.pending, .accepted, .declined].map(\.agendaLabel))
        XCTAssertEqual(labels.count, 3)
    }

    func testEachResponseHasADistinctColor() {
        let colors = Set([OutingResponse.pending, .accepted, .declined].map(\.agendaColor))
        XCTAssertEqual(colors.count, 3)
    }

    func testAcceptedIsLabeledAcceptee() {
        XCTAssertEqual(OutingResponse.accepted.agendaLabel, "Acceptée")
    }

    func testDeclinedIsLabeledRefusee() {
        XCTAssertEqual(OutingResponse.declined.agendaLabel, "Refusée")
    }

    func testPendingIsLabeledEnAttente() {
        XCTAssertEqual(OutingResponse.pending.agendaLabel, "En attente")
    }
}

final class AgendaReminderCooldownTests: XCTestCase {
    func testRecentReminderIsWithinCooldown() {
        let fiveMinutesAgo = DateHelpers.iso(Date().addingTimeInterval(-5 * 60))
        XCTAssertTrue(agendaRecentlyReminded(fiveMinutesAgo))
    }

    func testOldReminderIsOutsideCooldown() {
        let thirteenHoursAgo = DateHelpers.iso(Date().addingTimeInterval(-13 * 60 * 60))
        XCTAssertFalse(agendaRecentlyReminded(thirteenHoursAgo))
    }

    func testNilReminderIsNotRecentlyReminded() {
        XCTAssertFalse(agendaRecentlyReminded(nil))
    }

    func testUnparsableReminderIsNotRecentlyReminded() {
        XCTAssertFalse(agendaRecentlyReminded("not-a-date"))
    }
}

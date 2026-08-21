import XCTest
@testable import PoteAgenda

final class DateHelpersTests: XCTestCase {
    // MARK: - parse

    func testParseISOWithFractionalSeconds() {
        let date = DateHelpers.parse("2026-03-05T18:30:00.123Z")
        XCTAssertNotNil(date)
    }

    func testParseISOWithoutFractionalSeconds() {
        let date = DateHelpers.parse("2026-03-05T18:30:00Z")
        XCTAssertNotNil(date)
    }

    func testParsePostgRESTStyleWithOffset() {
        let date = DateHelpers.parse("2026-03-05T18:30:00+01:00")
        XCTAssertNotNil(date)
    }

    func testParsePostgRESTStyleWithSpaceSeparator() {
        let date = DateHelpers.parse("2026-03-05 18:30:00+01:00")
        XCTAssertNotNil(date)
    }

    func testParseInvalidStringReturnsNil() {
        XCTAssertNil(DateHelpers.parse("not-a-date"))
    }

    func testParseRoundTripsWithIso() {
        let original = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9, minute: 30, second: 0))!
        let string = DateHelpers.iso(original)
        let reparsed = DateHelpers.parse(string)
        XCTAssertNotNil(reparsed)
        XCTAssertEqual(reparsed!.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - dayBounds / weekBounds / monthBounds

    func testDayBoundsSpanExactlyOneDay() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 14, minute: 0))!
        let bounds = DateHelpers.dayBounds(for: day)
        XCTAssertEqual(bounds.start, Calendar.current.startOfDay(for: day))
        XCTAssertEqual(Calendar.current.dateComponents([.hour], from: bounds.start, to: bounds.end).hour, 24)
    }

    func testWeekBoundsStartOnMonday() {
        // Le mercredi 2026-03-04 doit produire une semaine qui démarre le lundi 2026-03-02.
        let wednesday = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4))!
        let bounds = DateHelpers.weekBounds(for: wednesday)
        XCTAssertEqual(Calendar.current.component(.weekday, from: bounds.start), 2, "La semaine doit démarrer un lundi")
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: bounds.start, to: bounds.end).day, 7)
    }

    func testWeekDatesReturnsSevenConsecutiveDays() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4))!
        let dates = DateHelpers.weekDates(for: day)
        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(Calendar.current.component(.weekday, from: dates.first!), 2)
        for i in 1..<dates.count {
            XCTAssertEqual(Calendar.current.dateComponents([.day], from: dates[i - 1], to: dates[i]).day, 1)
        }
    }

    func testMonthBoundsCoverEntireMonthWithFullWeeks() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let bounds = DateHelpers.monthBounds(for: day)
        // Les bornes doivent englober tout le mois calendaire.
        let monthRange = Calendar.current.range(of: .day, in: .month, for: day)!
        let firstOfMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let lastOfMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: monthRange.count))!
        XCTAssertLessThanOrEqual(bounds.start, firstOfMonth)
        XCTAssertGreaterThan(bounds.end, lastOfMonth)
        // Les bornes doivent elles-mêmes tomber sur des lundis (semaines complètes).
        XCTAssertEqual(Calendar.current.component(.weekday, from: bounds.start), 2)
    }

    func testMonthDatesAreAMultipleOfSeven() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        let dates = DateHelpers.monthDates(for: day)
        XCTAssertEqual(dates.count % 7, 0)
        XCTAssertGreaterThanOrEqual(dates.count, 28)
    }

    // MARK: - hourDate

    func testHourDateSetsExactHourAtStartOfDay() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 23, minute: 59))!
        let result = DateHelpers.hourDate(on: day, hour: 9)
        XCTAssertEqual(Calendar.current.component(.hour, from: result), 9)
        XCTAssertEqual(Calendar.current.component(.minute, from: result), 0)
        XCTAssertTrue(Calendar.current.isDate(result, inSameDayAs: day))
    }

    // MARK: - sameMonth

    func testSameMonthTrueForDifferentDaysSameMonth() {
        let a = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let b = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 28))!
        XCTAssertTrue(DateHelpers.sameMonth(a, b))
    }

    func testSameMonthFalseAcrossMonthBoundary() {
        let a = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let b = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        XCTAssertFalse(DateHelpers.sameMonth(a, b))
    }
}

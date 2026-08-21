import Foundation

enum DateHelpers {
    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeFallbackISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func makeDisplayTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func makeDisplayDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }

    private static func makeWeekdayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEE"
        return formatter
    }

    private static func makeMonthFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM"
        return formatter
    }

    private static func makeAPIDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func parse(_ value: String) -> Date? {
        makeISOFormatter().date(from: value)
            ?? makeFallbackISOFormatter().date(from: value)
            ?? parsePostgRESTDate(value)
    }

    private static func parsePostgRESTDate(_ value: String) -> Date? {
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd HH:mm:ssXXXXX"
        ] {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    static func iso(_ date: Date) -> String {
        makeISOFormatter().string(from: date)
    }

    static func apiDateString(_ date: Date) -> String {
        makeAPIDateFormatter().string(from: date)
    }

    static func displayTimeString(_ date: Date) -> String {
        makeDisplayTimeFormatter().string(from: date)
    }

    static func displayDateString(_ date: Date) -> String {
        makeDisplayDateFormatter().string(from: date)
    }

    static func displayDateTimeString(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        return "\(displayDateString(date)) à \(displayTimeString(date))"
    }

    static func weekdayString(_ date: Date) -> String {
        makeWeekdayFormatter().string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func shortDateString(_ date: Date) -> String {
        makeMonthFormatter().string(from: date)
    }

    static func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: date)
        return (start, Calendar.current.date(byAdding: .day, value: 1, to: start)!)
    }

    static func weekStart(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? Calendar.current.startOfDay(for: date)
    }

    static func weekBounds(for date: Date) -> (start: Date, end: Date) {
        let start = weekStart(for: date)
        return (start, Calendar.current.date(byAdding: .day, value: 7, to: start)!)
    }

    static func weekDates(for date: Date) -> [Date] {
        let start = weekStart(for: date)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    static func hourDate(on day: Date, hour: Int) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        return Calendar.current.date(byAdding: .hour, value: hour, to: start) ?? start
    }

    static func monthDates(for date: Date) -> [Date] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        let monthStart = calendar.date(from: components) ?? calendar.startOfDay(for: date)
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let weekdayOffset = (calendar.component(.weekday, from: monthStart) + 5) % 7
        let firstWeekStart = weekStart(for: monthStart)
        let visibleCount = Int(ceil(Double(range.count + weekdayOffset) / 7.0)) * 7
        return (0..<max(visibleCount, 35)).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeekStart) }
    }

    static func monthBounds(for date: Date) -> (start: Date, end: Date) {
        let dates = monthDates(for: date)
        let start = dates.first ?? Calendar.current.startOfDay(for: date)
        let last = dates.last ?? start
        return (start, Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    static func sameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, equalTo: rhs, toGranularity: .month)
    }
}

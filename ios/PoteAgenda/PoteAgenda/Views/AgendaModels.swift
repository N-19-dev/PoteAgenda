import SwiftUI

enum AgendaDisplayMode: String, CaseIterable, Identifiable {
    case day = "Jour"
    case week = "Semaine"
    case month = "Mois"

    var id: String { rawValue }
}

/// Ensemble de blocs qui se chevauchent dans le temps sur un même jour, en
/// vue semaine/mois : trop étroit pour un vrai layout en colonnes, on
/// n'affiche qu'un bloc + un badge de compte, et ce groupe sert à lister les
/// autres au tap.
struct AgendaOverlapGroup: Identifiable {
    let id = UUID()
    let blocks: [AgendaBlock]
}

struct AgendaDraftEvent: Identifiable {
    let id = UUID()
    let startsAt: Date
    let endsAt: Date
    /// Bornes du créneau où tout le monde est disponible, quand ce brouillon
    /// vient d'un tap sur une disponibilité commune : le début/fin restent
    /// ajustables mais ne doivent pas sortir de ce créneau.
    let slotStart: Date?
    let slotEnd: Date?

    init(day: Date) {
        let start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        self.startsAt = start
        self.endsAt = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        self.slotStart = nil
        self.slotEnd = nil
    }

    init(startsAt: Date, endsAt: Date, slotStart: Date? = nil, slotEnd: Date? = nil) {
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.slotStart = slotStart
        self.slotEnd = slotEnd
    }
}

struct AgendaBlock: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let startAt: String
    let endAt: String
    let color: String
    let ownEvent: CalendarEvent?
    let style: AgendaBlockStyle
    let details: AgendaBlockDetails

    var timeLabel: String {
        guard let start = DateHelpers.parse(startAt), let end = DateHelpers.parse(endAt) else { return "" }
        return "\(DateHelpers.displayTimeString(start)) - \(DateHelpers.displayTimeString(end))"
    }

    var dateRangeLabel: String {
        guard let start = DateHelpers.parse(startAt), let end = DateHelpers.parse(endAt) else { return "" }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(DateHelpers.displayDateString(start)), \(DateHelpers.displayTimeString(start)) - \(DateHelpers.displayTimeString(end))"
        }
        return "Du \(DateHelpers.displayDateString(start)) \(DateHelpers.displayTimeString(start)) au \(DateHelpers.displayDateString(end)) \(DateHelpers.displayTimeString(end))"
    }

    init?(event: CalendarEvent) {
        guard let id = event.id else { return nil }
        self.id = id
        self.title = event.title
        self.subtitle = nil
        self.startAt = event.startAt
        self.endAt = event.endAt
        self.color = event.color
        self.ownEvent = event
        self.style = .ownBusy
        self.details = .ownEvent(event)
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        startAt: String,
        endAt: String,
        color: String,
        ownEvent: CalendarEvent?,
        style: AgendaBlockStyle = .outing,
        details: AgendaBlockDetails? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.startAt = startAt
        self.endAt = endAt
        self.color = color
        self.ownEvent = ownEvent
        self.style = style
        self.details = details ?? .generic
    }
}

enum AgendaBlockDetails {
    case ownEvent(CalendarEvent)
    case receivedOuting(ReceivedOutingRow)
    case sentOuting(SentOutingRow)
    case friendBusy(BusyEvent, String, String)
    case friendPending(BusyEvent, String)
    case generic
}

enum AgendaBlockStyle: Equatable {
    case ownBusy
    case outing
    case friendBusy
    case friendPending

    var foregroundStyle: Color {
        switch self {
        case .friendBusy, .friendPending:
            return .secondary
        case .ownBusy, .outing:
            return .white
        }
    }

    func backgroundColor(for block: AgendaBlock) -> Color {
        switch self {
        case .friendBusy:
            return Color.poteBusyOther
        case .friendPending:
            return Color.potePendingOther
        case .ownBusy, .outing:
            return Color(hex: block.color)
        }
    }

    func borderColor(for block: AgendaBlock) -> Color {
        switch self {
        case .friendBusy:
            return Color.secondary.opacity(0.28)
        case .friendPending:
            return Color(hex: "#f97316").opacity(0.6)
        case .ownBusy, .outing:
            return Color(hex: block.color)
        }
    }

    var zIndex: Double {
        switch self {
        case .friendBusy, .friendPending:
            return 3
        case .ownBusy:
            return 2
        case .outing:
            return 1
        }
    }
}

private let agendaRemindCooldownSeconds: TimeInterval = 12 * 60 * 60

func agendaRecentlyReminded(_ remindedAt: String?) -> Bool {
    guard let remindedAt, let date = DateHelpers.parse(remindedAt) else { return false }
    return Date().timeIntervalSince(date) < agendaRemindCooldownSeconds
}

extension Color {
    static var poteGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color.gray.opacity(0.08)
        #endif
    }

    static var poteSecondaryGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.white
        #endif
    }

    static var poteSeparator: Color {
        #if os(iOS)
        Color(uiColor: .separator)
        #else
        Color.gray
        #endif
    }

    static var poteBusyOther: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #else
        Color.gray.opacity(0.24)
        #endif
    }

    /// Signale qu'un ami est sollicité pour un truc sans dire "occupé" :
    /// même teinte que le badge "En attente" des invitations (#f97316),
    /// mais très pâle pour ne pas se confondre avec une vraie
    /// indisponibilité (poteBusyOther) — le texte reste toujours en
    /// .secondary par-dessus, jamais dans cette teinte, pour la lisibilité.
    static var potePendingOther: Color {
        Color(hex: "#f97316").opacity(0.12)
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension OutingResponse {
    var agendaLabel: String {
        switch self {
        case .pending: "En attente"
        case .accepted: "Acceptée"
        case .declined: "Refusée"
        }
    }

    var agendaColor: String {
        switch self {
        case .pending: "#f97316"
        case .accepted: "#22c55e"
        case .declined: "#ef4444"
        }
    }
}

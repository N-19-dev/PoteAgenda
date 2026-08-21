import EventKit
import Foundation

@MainActor
final class EventKitService {
    static let shared = EventKitService()

    static let horizonDays = 90
    static let importedEventColor = "#0ea5e9"

    private let store = EKEventStore()

    private init() {}

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestAccess() async throws -> Bool {
        // `requestFullAccessToEvents()` (la variante async native) declenche un
        // "unsafeForcedSync called from Swift Concurrent context" sur iOS 17/18 :
        // son pont interne vers tccd bloque un thread du pool cooperatif de Swift
        // Concurrency. On repasse par l'ancienne API a completion handler (toujours
        // fonctionnelle et equivalente a un acces complet malgre la depreciation)
        // pour eviter ce pont natif casse.
        let granted: Bool = try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { throw AppError.message("Accès au calendrier refusé. Autorise PoteAgenda dans Réglages > Confidentialité > Calendriers.") }
        return granted
    }

    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func calendar(withIdentifier id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    /// - Parameter includeRealTitles: si `false` (comportement par défaut), le
    ///   titre réel de l'événement n'est jamais lu ni envoyé au backend : seul
    ///   "Occupé" est stocké. Les vrais titres ne doivent quitter l'appareil
    ///   que si l'utilisateur a explicitement activé l'import des titres
    ///   réels dans les réglages.
    func fetchInputEvents(for calendar: EKCalendar, includeRealTitles: Bool) -> [CalendarEventInputPayload] {
        let now = Date()
        guard let horizonEnd = Calendar.current.date(byAdding: .day, value: Self.horizonDays, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: horizonEnd, calendars: [calendar])
        return store.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate, start < end else { return nil }
            let title: String
            if includeRealTitles {
                let trimmedTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                title = (trimmedTitle?.isEmpty == false) ? trimmedTitle! : "Occupé"
            } else {
                title = "Occupé"
            }
            let baseId = event.eventIdentifier ?? UUID().uuidString
            return CalendarEventInputPayload(
                title: title,
                start_at: DateHelpers.iso(start),
                end_at: DateHelpers.iso(end),
                color: Self.importedEventColor,
                external_uid: "\(baseId)-\(DateHelpers.iso(start))"
            )
        }
    }

    /// Nombre d'événements du calendrier `calendar` sur l'horizon d'import,
    /// pour afficher un résumé avant la première synchronisation.
    func countUpcomingEvents(for calendar: EKCalendar) -> Int {
        let now = Date()
        guard let horizonEnd = Calendar.current.date(byAdding: .day, value: Self.horizonDays, to: now) else { return 0 }
        let predicate = store.predicateForEvents(withStart: now, end: horizonEnd, calendars: [calendar])
        return store.events(matching: predicate).filter { event in
            guard let start = event.startDate, let end = event.endDate else { return false }
            return start < end
        }.count
    }
}

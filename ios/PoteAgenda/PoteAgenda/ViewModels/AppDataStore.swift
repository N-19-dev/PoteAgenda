import EventKit
import Foundation
import UserNotifications

@MainActor
final class AppDataStore: ObservableObject {
    @Published var selectedDay = Date()
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var friendsBusyEvents: [BusyEvent] = []
    @Published var friendsPendingOutings: [BusyEvent] = []
    @Published var friends: [FriendRow] = []
    @Published var groups: [PoteGroup] = []
    @Published var selectedGroup: PoteGroup?
    @Published var selectedGroupMembers: [GroupMemberRow] = []
    @Published var busyEvents: [BusyEvent] = []
    @Published var outings: [ReceivedOutingRow] = []
    @Published var sentOutings: [SentOutingRow] = []
    @Published var agendaSelectedFriendIds = Set<String>()
    @Published var agendaShowingGroupBusyEvents = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var calendarSources: [CalendarSource] = []
    @Published var deviceCalendars: [EKCalendar] = []
    @Published var deviceCalendarAuthorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var travelMode: TravelMode {
        didSet {
            UserDefaults.standard.set(travelMode.rawValue, forKey: Self.travelModeDefaultsKey)
            Task { await scheduleDepartureReminders() }
        }
    }
    /// Opt-in explicite, distinct de l'autorisation système : même avec la
    /// position accordée à iOS, l'utilisateur peut couper la fonctionnalité
    /// sans révoquer l'autorisation.
    @Published var departureRemindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(departureRemindersEnabled, forKey: Self.departureRemindersEnabledDefaultsKey)
            if departureRemindersEnabled {
                LocationService.shared.requestAuthorizationIfNeeded()
            }
            Task { await scheduleDepartureReminders() }
        }
    }

    private static let travelModeDefaultsKey = "poteagenda.travelMode"
    private static let departureRemindersEnabledDefaultsKey = "poteagenda.departureRemindersEnabled"

    private let service: SupabaseService
    private let session: AuthSession
    private var hasLoadedOutings = false
    private var knownReceivedOutingIds = Set<String>()
    private var knownReminderKeys = Set<String>()
    private var hasLoadedMentions = false
    private var knownMentionMessageIds = Set<String>()

    init(service: SupabaseService, session: AuthSession) {
        self.service = service
        self.session = session
        let storedTravelMode = UserDefaults.standard.string(forKey: Self.travelModeDefaultsKey).flatMap(TravelMode.init(rawValue:))
        self.travelMode = storedTravelMode ?? .automobile
        self.departureRemindersEnabled = UserDefaults.standard.bool(forKey: Self.departureRemindersEnabledDefaultsKey)
    }

    func refreshAll() async {
        await refreshFriends()
        await refreshGroups()
        await refreshAgenda()
        await refreshOutings()
    }

    func refreshAgenda() async {
        let bounds = DateHelpers.monthBounds(for: selectedDay)
        await refreshAgenda(start: bounds.start, end: bounds.end)
    }

    func refreshAgenda(start: Date, end: Date) async {
        await run {
            calendarEvents = try await service.calendarEvents(session: session, start: start, end: end)
            do {
                friendsBusyEvents = try await service.friendsBusyEvents(
                    session: session,
                    friendIds: acceptedFriendIds,
                    start: start,
                    end: end
                )
            } catch {
                if isCancellation(error) { throw error }
                friendsBusyEvents = []
                errorMessage = "Impossible de charger les indisponibilités des amis : \(error.localizedDescription)"
            }
            do {
                friendsPendingOutings = try await service.friendsPendingOutings(
                    session: session,
                    friendIds: acceptedFriendIds,
                    start: start,
                    end: end
                )
            } catch {
                if isCancellation(error) { throw error }
                friendsPendingOutings = []
            }
            if let selectedGroup {
                do {
                    busyEvents = try await service.busyEvents(
                        session: session,
                        groupId: selectedGroup.id,
                        start: start,
                        end: end
                    )
            } catch {
                if isCancellation(error) { throw error }
                busyEvents = []
            }
            }
        }
    }

    func addEvent(title: String, startsAt: Date, endsAt: Date, color: String) async {
        await run {
            try await service.addCalendarEvent(session: session, title: title, startsAt: startsAt, endsAt: endsAt, color: color)
            let bounds = DateHelpers.monthBounds(for: selectedDay)
            calendarEvents = try await service.calendarEvents(session: session, start: bounds.start, end: bounds.end)
            await refreshAvailabilitySignals()
        }
    }

    func deleteEvent(_ event: CalendarEvent) async {
        guard let id = event.id else { return }
        await run {
            try await service.deleteCalendarEvent(session: session, id: id)
            calendarEvents.removeAll { $0.id == id }
            await refreshAvailabilitySignals()
        }
    }

    /// Une indisponibilité ajoutée/supprimée, ou une invitation
    /// créée/répondue/annulée, change ce que les autres voient de ma
    /// disponibilité (groupe, amis). Sans ça, les vues qui affichent cette
    /// disponibilité (groupe sélectionné, agenda ami) restaient périmées
    /// jusqu'au prochain refresh complet.
    private func refreshAvailabilitySignals() async {
        let bounds = DateHelpers.monthBounds(for: selectedDay)
        do {
            friendsBusyEvents = try await service.friendsBusyEvents(
                session: session,
                friendIds: acceptedFriendIds,
                start: bounds.start,
                end: bounds.end
            )
        } catch {
            if !isCancellation(error) { friendsBusyEvents = [] }
        }
        do {
            friendsPendingOutings = try await service.friendsPendingOutings(
                session: session,
                friendIds: acceptedFriendIds,
                start: bounds.start,
                end: bounds.end
            )
        } catch {
            if !isCancellation(error) { friendsPendingOutings = [] }
        }
        if let selectedGroup {
            do {
                busyEvents = try await service.busyEvents(session: session, groupId: selectedGroup.id, start: bounds.start, end: bounds.end)
            } catch {
                if !isCancellation(error) { busyEvents = [] }
            }
        }
    }

    func refreshCalendarSources() async {
        await run {
            calendarSources = try await service.calendarSources(session: session)
        }
    }

    func loadDeviceCalendarsIfAuthorized() {
        deviceCalendarAuthorizationStatus = EventKitService.shared.authorizationStatus
        deviceCalendars = deviceCalendarAuthorizationStatus == .fullAccess
            ? EventKitService.shared.availableCalendars()
            : []
    }

    func requestDeviceCalendarAccess() async {
        await run {
            try await EventKitService.shared.requestAccess()
            loadDeviceCalendarsIfAuthorized()
        }
    }

    func connectDeviceCalendar(_ calendar: EKCalendar) async {
        await run {
            let source = try await service.createCalendarSource(
                session: session,
                label: calendar.title,
                kind: "device",
                deviceCalendarId: calendar.calendarIdentifier
            )
            try await service.resyncCalendarSource(
                session: session,
                sourceId: source.id,
                events: EventKitService.shared.fetchInputEvents(for: calendar)
            )
            calendarSources = try await service.calendarSources(session: session)
            try await refreshAgendaAfterSourceChange()
        }
    }

    func resyncDeviceCalendarSource(_ source: CalendarSource) async {
        guard
            let deviceCalendarId = source.deviceCalendarId,
            let calendar = EventKitService.shared.calendar(withIdentifier: deviceCalendarId)
        else {
            errorMessage = "Calendrier introuvable sur l'appareil. Reconnecte-le depuis la liste ci-dessus."
            return
        }
        await run {
            try await service.resyncCalendarSource(
                session: session,
                sourceId: source.id,
                events: EventKitService.shared.fetchInputEvents(for: calendar)
            )
            calendarSources = try await service.calendarSources(session: session)
            try await refreshAgendaAfterSourceChange()
        }
    }

    func deleteCalendarSource(_ source: CalendarSource) async {
        await run {
            try await service.deleteCalendarSource(session: session, id: source.id)
            calendarSources.removeAll { $0.id == source.id }
            try await refreshAgendaAfterSourceChange()
        }
    }

    private func refreshAgendaAfterSourceChange() async throws {
        let bounds = DateHelpers.monthBounds(for: selectedDay)
        calendarEvents = try await service.calendarEvents(session: session, start: bounds.start, end: bounds.end)
    }

    func refreshFriends() async {
        await run {
            friends = try await service.friendships(session: session)
            let bounds = DateHelpers.monthBounds(for: selectedDay)
            do {
                friendsBusyEvents = try await service.friendsBusyEvents(
                    session: session,
                    friendIds: acceptedFriendIds,
                    start: bounds.start,
                    end: bounds.end
                )
            } catch {
                if isCancellation(error) { throw error }
                friendsBusyEvents = []
                errorMessage = "Impossible de charger les indisponibilités des amis : \(error.localizedDescription)"
            }
            do {
                friendsPendingOutings = try await service.friendsPendingOutings(
                    session: session,
                    friendIds: acceptedFriendIds,
                    start: bounds.start,
                    end: bounds.end
                )
            } catch {
                if isCancellation(error) { throw error }
                friendsPendingOutings = []
            }
        }
    }

    func searchProfiles(_ query: String) async throws -> [ProfileSearchResult] {
        try await service.searchProfiles(session: session, query: query)
    }

    func sendFriendRequest(_ profile: ProfileSearchResult) async {
        await run {
            try await service.sendFriendRequest(session: session, addresseeId: profile.id)
            friends = try await service.friendships(session: session)
        }
    }

    func respondToFriendship(_ friendship: Friendship, accept: Bool) async {
        await run {
            try await service.respondToFriendRequest(session: session, friendshipId: friendship.id, accept: accept)
            friends = try await service.friendships(session: session)
        }
    }

    func refreshGroups() async {
        await run {
            groups = try await service.groups(session: session)
            selectedGroup = selectedGroup.flatMap { current in groups.first { $0.id == current.id } } ?? groups.first
            if let selectedGroup {
                selectedGroupMembers = try await service.groupMembers(session: session, groupId: selectedGroup.id)
                let bounds = DateHelpers.monthBounds(for: selectedDay)
                busyEvents = try await service.busyEvents(session: session, groupId: selectedGroup.id, start: bounds.start, end: bounds.end)
            } else {
                selectedGroupMembers = []
                busyEvents = []
            }
        }
    }

    func createGroup(name: String, description: String?) async {
        await createGroup(name: name, description: description, memberIds: [])
    }

    func createGroup(name: String, description: String?, memberIds: [String]) async {
        await run {
            try await service.createGroup(session: session, name: name, description: description, memberIds: memberIds)
            groups = try await service.groups(session: session)
            selectedGroup = groups.first
            if let selectedGroup {
                selectedGroupMembers = try await service.groupMembers(session: session, groupId: selectedGroup.id)
            }
        }
    }

    func updateGroup(_ group: PoteGroup, name: String, description: String?) async {
        await run {
            try await service.updateGroup(session: session, groupId: group.id, name: name, description: description)
            groups = try await service.groups(session: session)
            selectedGroup = groups.first { $0.id == group.id } ?? selectedGroup
        }
    }

    func selectGroup(_ group: PoteGroup) async {
        selectedGroup = group
        await run {
            selectedGroupMembers = try await service.groupMembers(session: session, groupId: group.id)
            let bounds = DateHelpers.monthBounds(for: selectedDay)
            busyEvents = try await service.busyEvents(session: session, groupId: group.id, start: bounds.start, end: bounds.end)
        }
    }

    func addMembers(to group: PoteGroup, userIds: [String]) async {
        await run {
            try await service.addGroupMembers(session: session, groupId: group.id, userIds: userIds)
            selectedGroupMembers = try await service.groupMembers(session: session, groupId: group.id)
        }
    }

    func removeMember(from group: PoteGroup, userId: String) async {
        await run {
            try await service.removeGroupMember(session: session, groupId: group.id, userId: userId)
            selectedGroupMembers.removeAll { $0.member.userId == userId }
        }
    }

    func refreshOutings() async {
        await run {
            let nextOutings = try await service.outings(session: session)
            let nextSentOutings = try await service.sentOutings(session: session)
            await notifyForOutingChanges(nextOutings)
            outings = nextOutings
            sentOutings = nextSentOutings
            await refreshMentions()
            await scheduleDepartureReminders()
        }
    }

    func requestLocationAuthorizationIfNeeded() {
        LocationService.shared.requestAuthorizationIfNeeded()
    }

    /// Rappel local "pars dans 15 min" calculé depuis le temps de trajet estimé
    /// (position actuelle -> adresse de la sortie). Best effort : sans
    /// autorisation de localisation, sans adresse résolvable ou sans trajet
    /// calculable, on ne programme simplement rien.
    private func scheduleDepartureReminders() async {
        guard departureRemindersEnabled else {
            await InvitationNotificationService.shared.pruneDepartureReminders(keeping: [])
            return
        }

        let eligibleOutings = departureReminderEligibleOutings()
        await InvitationNotificationService.shared.pruneDepartureReminders(keeping: Set(eligibleOutings.map(\.id)))
        guard !eligibleOutings.isEmpty else { return }

        guard let coordinate = try? await LocationService.shared.currentCoordinate() else { return }

        for outing in eligibleOutings {
            guard let location = outing.location, !location.isEmpty else { continue }
            guard let startsAt = DateHelpers.parse(outing.startsAt) else { continue }
            guard let travelTime = try? await TravelTimeEstimator.travelTime(from: coordinate, toAddress: location, mode: travelMode) else { continue }

            let notifyAt = startsAt.addingTimeInterval(-travelTime - 15 * 60)
            await InvitationNotificationService.shared.scheduleDepartureReminder(
                for: outing,
                notifyAt: notifyAt,
                minutesBeforeDeparture: 15
            )
        }
    }

    private func departureReminderEligibleOutings() -> [Outing] {
        let now = Date()
        let acceptedReceived = outings.filter { $0.response == .accepted }.map(\.outing)
        let owned = sentOutings.map(\.outing)

        return (acceptedReceived + owned).filter { outing in
            guard outing.cancelledAt == nil else { return false }
            guard let location = outing.location, !location.isEmpty else { return false }
            guard let startsAt = DateHelpers.parse(outing.startsAt) else { return false }
            return startsAt > now
        }
    }

    /// Notification locale "best effort" quand l'utilisateur a été tagué dans un
    /// message : comme pour les invitations/relances, il n'y a pas de push serveur,
    /// donc ça ne se déclenche qu'aux moments où l'app rafraîchit déjà les sorties
    /// (lancement, ouverture de l'onglet Invitations, pull-to-refresh).
    private func refreshMentions() async {
        let outingIds = Set(outings.map(\.outing.id) + sentOutings.map(\.outing.id))
        guard !outingIds.isEmpty else { return }
        do {
            let messages = try await service.outingMentionMessages(session: session, outingIds: Array(outingIds))
            await notifyForNewMentions(messages)
        } catch {
            // Best effort : une erreur ici ne doit pas polluer errorMessage.
        }
    }

    private func notifyForNewMentions(_ messages: [OutingMessage]) async {
        defer {
            hasLoadedMentions = true
            knownMentionMessageIds.formUnion(messages.map(\.id))
        }
        guard hasLoadedMentions else { return }

        let titleById = Dictionary(
            uniqueKeysWithValues: (outings.map { ($0.outing.id, $0.outing.title) } + sentOutings.map { ($0.outing.id, $0.outing.title) })
        )

        for message in messages where message.senderId != currentUserId && !knownMentionMessageIds.contains(message.id) {
            await InvitationNotificationService.shared.notifyMention(
                messageId: message.id,
                outingTitle: titleById[message.outingId] ?? "une sortie",
                senderName: message.profile?.username,
                body: message.body
            )
        }
    }

    func respondToOuting(_ outing: Outing, response: OutingResponse) async {
        await run {
            try await service.respondToOuting(session: session, outingId: outing.id, response: response)
            outings = try await service.outings(session: session)
            sentOutings = try await service.sentOutings(session: session)
            await refreshAvailabilitySignals()
        }
    }

    func setOutingConfirmed(_ outing: Outing, confirmed: Bool) async {
        await run {
            try await service.setOutingConfirmed(session: session, outingId: outing.id, confirmed: confirmed)
            sentOutings = try await service.sentOutings(session: session)
            outings = try await service.outings(session: session)
        }
    }

    func cancelOuting(_ outing: Outing) async {
        await run {
            try await service.cancelOuting(session: session, outingId: outing.id)
            sentOutings = try await service.sentOutings(session: session)
            outings = try await service.outings(session: session)
            await refreshAvailabilitySignals()
        }
    }

    func outingMessages(outingId: String) async throws -> [OutingMessage] {
        try await service.outingMessages(session: session, outingId: outingId)
    }

    func sendOutingMessage(outingId: String, body: String, mentionedUserIds: [String] = []) async throws {
        try await service.sendOutingMessage(session: session, outingId: outingId, body: body, mentionedUserIds: mentionedUserIds)
    }

    func outingParticipants(outingId: String) async throws -> [OutingParticipantRow] {
        try await service.outingParticipantsWithProfiles(session: session, outingId: outingId)
    }

    @discardableResult
    func remindOutingParticipant(outing: Outing, participant: OutingParticipant) async -> Bool {
        await runReturning {
            try await service.remindOutingParticipant(
                session: session,
                outingId: outing.id,
                userId: participant.userId
            )
            sentOutings = try await service.sentOutings(session: session)
        }
    }

    @discardableResult
    func remindPendingOutingParticipants(outing: Outing, participants: [OutingParticipant]) async -> Bool {
        let pendingParticipants = participants.filter { $0.response == .pending }
        guard !pendingParticipants.isEmpty else { return false }
        return await runReturning {
            for participant in pendingParticipants {
                try await service.remindOutingParticipant(
                    session: session,
                    outingId: outing.id,
                    userId: participant.userId
                )
            }
            sentOutings = try await service.sentOutings(session: session)
        }
    }

    func createOuting(title: String, startsAt: Date, endsAt: Date, location: String?, note: String?, friendIds: [String]) async {
        await createOuting(title: title, startsAt: startsAt, endsAt: endsAt, location: location, note: note, friendIds: friendIds, groupId: nil)
    }

    func createOuting(title: String, startsAt: Date, endsAt: Date, location: String?, note: String?, friendIds: [String], groupId: String?) async {
        let group = groupId.flatMap { id in groups.first { $0.id == id } }
        await createOuting(title: title, startsAt: startsAt, endsAt: endsAt, location: location, note: note, friendIds: friendIds, group: group)
    }

    func createOuting(title: String, startsAt: Date, endsAt: Date, location: String?, note: String?, friendIds: [String], group: PoteGroup?) async {
        await run {
            var inviteeIds = Set(friendIds)
            if let group {
                let members = selectedGroup?.id == group.id
                    ? selectedGroupMembers
                    : try await service.groupMembers(session: session, groupId: group.id)
                inviteeIds.formUnion(members.map { $0.member.userId })
                inviteeIds.remove(currentUserId)
            }

            try await service.createOuting(
                session: session,
                title: title,
                startsAt: startsAt,
                endsAt: endsAt,
                location: location,
                note: note,
                friendIds: Array(inviteeIds),
                groupId: group?.id
            )
            sentOutings = try await service.sentOutings(session: session)
            outings = try await service.outings(session: session)
            await refreshAvailabilitySignals()
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await operation()
        } catch {
            if isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private func runReturning(_ operation: () async throws -> Void) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await operation()
            return true
        } catch {
            if isCancellation(error) { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    var acceptedFriends: [FriendRow] {
        friends.filter { $0.friendship.status == .accepted }
    }

    func friendUserId(for row: FriendRow) -> String {
        row.friendship.requesterId == session.user.id ? row.friendship.addresseeId : row.friendship.requesterId
    }

    private var acceptedFriendIds: [String] {
        acceptedFriends.map { friendUserId(for: $0) }
    }

    var currentUserId: String {
        session.user.id
    }

    func requestNotificationAuthorization() async {
        await InvitationNotificationService.shared.requestAuthorization()
    }

    private func notifyForOutingChanges(_ nextOutings: [ReceivedOutingRow]) async {
        let nextIds = Set(nextOutings.map(\.outing.id))
        let nextReminderKeys: Set<String> = Set(nextOutings.compactMap { row in
            guard row.response == .pending, let remindedAt = row.participant.remindedAt else { return nil }
            return "\(row.outing.id)-\(remindedAt)"
        })

        defer {
            hasLoadedOutings = true
            knownReceivedOutingIds = nextIds
            knownReminderKeys = nextReminderKeys
        }

        guard hasLoadedOutings else { return }

        for row in nextOutings where row.response == .pending && !knownReceivedOutingIds.contains(row.outing.id) {
            await InvitationNotificationService.shared.notifyNewInvitation(row.outing)
        }

        for row in nextOutings where row.response == .pending {
            guard
                let remindedAt = row.participant.remindedAt,
                !knownReminderKeys.contains("\(row.outing.id)-\(remindedAt)")
            else { continue }
            await InvitationNotificationService.shared.notifyReminder(row.outing)
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

@MainActor
final class InvitationNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = InvitationNotificationService()

    private let center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false

    private override init() {
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func requestAuthorization() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func notifyNewInvitation(_ outing: Outing) async {
        await requestAuthorization()
        await schedule(
            identifier: "outing-invitation-\(outing.id)",
            title: "Nouvelle invitation",
            body: outing.title
        )
    }

    func notifyReminder(_ outing: Outing) async {
        await requestAuthorization()
        await schedule(
            identifier: "outing-reminder-\(outing.id)-\(DateHelpers.iso(Date()))",
            title: "Relance d'invitation",
            body: outing.title
        )
    }

    func notifyMention(messageId: String, outingTitle: String, senderName: String?, body: String) async {
        await requestAuthorization()
        let title = senderName.map { "\($0) t'a mentionné dans \(outingTitle)" }
            ?? "Tu as été mentionné dans \(outingTitle)"
        await schedule(identifier: "outing-mention-\(messageId)", title: title, body: body)
    }

    private static let departureReminderPrefix = "outing-departure-"

    /// Remplace le rappel de départ déjà programmé pour cette sortie (même
    /// identifiant = `add` écrase l'ancien), pour refléter un trajet
    /// recalculé à chaque rafraîchissement.
    func scheduleDepartureReminder(for outing: Outing, notifyAt: Date, minutesBeforeDeparture: Int) async {
        guard notifyAt.timeIntervalSinceNow > 0 else { return }
        await requestAuthorization()
        await schedule(
            identifier: "\(Self.departureReminderPrefix)\(outing.id)",
            title: "C'est bientôt l'heure de partir",
            body: "Pars dans \(minutesBeforeDeparture) min pour arriver à l'heure à \(outing.title).",
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: notifyAt.timeIntervalSinceNow, repeats: false)
        )
    }

    func pruneDepartureReminders(keeping outingIds: Set<String>) async {
        let pending = await center.pendingNotificationRequests()
        let staleIds = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.departureReminderPrefix) }
            .filter { !outingIds.contains(String($0.dropFirst(Self.departureReminderPrefix.count))) }
        guard !staleIds.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: staleIds)
    }

    private func schedule(identifier: String, title: String, body: String, trigger: UNNotificationTrigger? = nil) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}

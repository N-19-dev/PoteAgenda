import Foundation

@MainActor
final class SupabaseService {
    private let config: SupabaseConfig
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(config: SupabaseConfig) {
        self.config = config
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await request(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            method: "POST",
            session: nil,
            body: EmailPasswordPayload(email: email, password: password)
        )
    }

    func signUp(email: String, password: String, username: String) async throws -> AuthSession? {
        let data = try await rawRequest(
            path: "/auth/v1/signup",
            method: "POST",
            session: nil,
            body: SignUpPayload(email: email, password: password, data: SignUpMetadata(username: username))
        )
        return try? decoder.decode(AuthSession.self, from: data)
    }

    func refresh(session: AuthSession) async throws -> AuthSession {
        try await request(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            session: nil,
            body: RefreshPayload(refresh_token: session.refreshToken)
        )
    }

    func signOut(session: AuthSession) async throws {
        _ = try await rawRequest(path: "/auth/v1/logout", method: "POST", session: session, body: EmptyBody())
    }

    func calendarEvents(session: AuthSession, day: Date) async throws -> [CalendarEvent] {
        let bounds = DateHelpers.dayBounds(for: day)
        return try await calendarEvents(session: session, start: bounds.start, end: bounds.end)
    }

    func calendarEvents(session: AuthSession, start: Date, end: Date) async throws -> [CalendarEvent] {
        return try await request(
            path: "/rest/v1/calendar_events",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "start_at", value: "lt.\(DateHelpers.iso(end))"),
                .init(name: "end_at", value: "gt.\(DateHelpers.iso(start))"),
                .init(name: "order", value: "start_at.asc")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
    }

    func addCalendarEvent(session: AuthSession, title: String, startsAt: Date, endsAt: Date, color: String) async throws {
        let payload = NewCalendarEvent(
            user_id: session.user.id,
            title: title,
            start_at: DateHelpers.iso(startsAt),
            end_at: DateHelpers.iso(endsAt),
            color: color,
            source: "manual"
        )
        _ = try await rawRequest(path: "/rest/v1/calendar_events", method: "POST", session: session, body: payload)
    }

    func deleteCalendarEvent(session: AuthSession, id: String) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/calendar_events",
            queryItems: [.init(name: "id", value: "eq.\(id)")],
            method: "DELETE",
            session: session,
            body: Optional<EmptyBody>.none
        )
    }

    func calendarSources(session: AuthSession) async throws -> [CalendarSource] {
        return try await request(
            path: "/rest/v1/calendar_sources",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "order", value: "created_at.desc")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
    }

    func createCalendarSource(session: AuthSession, label: String, kind: String, deviceCalendarId: String?) async throws -> CalendarSource {
        let created: [CalendarSource] = try await request(
            path: "/rest/v1/calendar_sources",
            queryItems: [.init(name: "select", value: "*")],
            method: "POST",
            session: session,
            body: NewCalendarSource(user_id: session.user.id, label: label, kind: kind, device_calendar_id: deviceCalendarId)
        )
        guard let source = created.first else { throw AppError.message("Creation du calendrier impossible.") }
        return source
    }

    func deleteCalendarSource(session: AuthSession, id: String) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/calendar_sources",
            queryItems: [.init(name: "id", value: "eq.\(id)")],
            method: "DELETE",
            session: session,
            body: Optional<EmptyBody>.none
        )
    }

    func resyncCalendarSource(session: AuthSession, sourceId: String, events: [CalendarEventInputPayload]) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/rpc/resync_calendar_source",
            method: "POST",
            session: session,
            body: ResyncCalendarSourcePayload(p_source_id: sourceId, p_events: events)
        )
    }

    func searchProfiles(session: AuthSession, query: String) async throws -> [Profile] {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return [] }
        return try await rpc(session: session, name: "search_profiles", body: ["p_query": query])
    }

    func friendships(session: AuthSession) async throws -> [FriendRow] {
        let userId = session.user.id
        let rows: [Friendship] = try await request(
            path: "/rest/v1/friendships",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "or", value: "(requester_id.eq.\(userId),addressee_id.eq.\(userId))"),
                .init(name: "order", value: "created_at.desc")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        let ids = rows.map { $0.requesterId == userId ? $0.addresseeId : $0.requesterId }
        let profiles = try await profiles(session: session, ids: ids)
        return rows.map { row in
            let otherId = row.requesterId == userId ? row.addresseeId : row.requesterId
            return FriendRow(friendship: row, profile: profiles[otherId])
        }
    }

    func sendFriendRequest(session: AuthSession, addresseeId: String) async throws {
        let body = ["requester_id": session.user.id, "addressee_id": addresseeId, "status": "pending"]
        _ = try await rawRequest(path: "/rest/v1/friendships", method: "POST", session: session, body: body)
    }

    func respondToFriendRequest(session: AuthSession, friendshipId: String, accept: Bool) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/friendships",
            queryItems: [.init(name: "id", value: "eq.\(friendshipId)")],
            method: "PATCH",
            session: session,
            body: ["status": accept ? "accepted" : "declined"]
        )
    }

    func groups(session: AuthSession) async throws -> [PoteGroup] {
        let memberships: [GroupMember] = try await request(
            path: "/rest/v1/group_members",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "user_id", value: "eq.\(session.user.id)")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        return try await groups(session: session, ids: memberships.map(\.groupId))
    }

    func createGroup(session: AuthSession, name: String, description: String?) async throws {
        try await createGroup(session: session, name: name, description: description, memberIds: [])
    }

    func createGroup(session: AuthSession, name: String, description: String?, memberIds: [String]) async throws {
        struct NewGroup: Encodable {
            let name: String
            let description: String?
            let owner_id: String
        }
        let created: [PoteGroup] = try await request(
            path: "/rest/v1/groups",
            queryItems: [.init(name: "select", value: "*")],
            method: "POST",
            session: session,
            body: NewGroup(name: name, description: description, owner_id: session.user.id)
        )
        guard let group = created.first else { return }
        let rows = [NewGroupMember(group_id: group.id, user_id: session.user.id, role: "owner")]
            + Array(Set(memberIds)).filter { $0 != session.user.id }.map { userId in
                NewGroupMember(group_id: group.id, user_id: userId, role: "member")
            }
        _ = try await rawRequest(path: "/rest/v1/group_members", method: "POST", session: session, body: rows)
    }

    func updateGroup(session: AuthSession, groupId: String, name: String, description: String?) async throws {
        struct UpdateGroup: Encodable {
            let name: String
            let description: String?
        }
        _ = try await rawRequest(
            path: "/rest/v1/groups",
            queryItems: [.init(name: "id", value: "eq.\(groupId)")],
            method: "PATCH",
            session: session,
            body: UpdateGroup(name: name, description: description)
        )
    }

    func groupMembers(session: AuthSession, groupId: String) async throws -> [GroupMemberRow] {
        let members: [GroupMember] = try await request(
            path: "/rest/v1/group_members",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "group_id", value: "eq.\(groupId)"),
                .init(name: "order", value: "role.desc,joined_at.asc")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        let profilesById = try await profiles(session: session, ids: members.map(\.userId))
        return members.map { member in
            GroupMemberRow(member: member, profile: profilesById[member.userId])
        }
    }

    func addGroupMembers(session: AuthSession, groupId: String, userIds: [String]) async throws {
        let rows = Array(Set(userIds)).filter { $0 != session.user.id }.map { userId in
            NewGroupMember(group_id: groupId, user_id: userId, role: "member")
        }
        guard !rows.isEmpty else { return }
        _ = try await rawRequest(path: "/rest/v1/group_members", method: "POST", session: session, body: rows)
    }

    func removeGroupMember(session: AuthSession, groupId: String, userId: String) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/group_members",
            queryItems: [
                .init(name: "group_id", value: "eq.\(groupId)"),
                .init(name: "user_id", value: "eq.\(userId)")
            ],
            method: "DELETE",
            session: session,
            body: Optional<EmptyBody>.none
        )
    }

    func busyEvents(session: AuthSession, groupId: String, day: Date) async throws -> [BusyEvent] {
        let bounds = DateHelpers.dayBounds(for: day)
        return try await busyEvents(session: session, groupId: groupId, start: bounds.start, end: bounds.end)
    }

    func busyEvents(session: AuthSession, groupId: String, start: Date, end: Date) async throws -> [BusyEvent] {
        return try await rpc(
            session: session,
            name: "get_group_busy_events",
            body: [
                "p_group_id": groupId,
                "p_range_start": DateHelpers.apiDateString(start),
                "p_range_end": DateHelpers.apiDateString(end)
            ]
        )
    }

    func friendsBusyEvents(session: AuthSession, friendIds: [String], start: Date, end: Date) async throws -> [BusyEvent] {
        guard !friendIds.isEmpty else { return [] }
        return try await rpc(
            session: session,
            name: "get_friends_busy_events",
            body: FriendsBusyEventsPayload(
                p_friend_ids: friendIds,
                p_range_start: DateHelpers.apiDateString(start),
                p_range_end: DateHelpers.apiDateString(end)
            )
        )
    }

    func outings(session: AuthSession) async throws -> [ReceivedOutingRow] {
        let participants: [OutingParticipant] = try await request(
            path: "/rest/v1/outing_participants",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "user_id", value: "eq.\(session.user.id)")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        let outingsById = try await outings(session: session, ids: participants.map(\.outingId))
        return participants.compactMap { participant in
            guard let outing = outingsById[participant.outingId], outing.cancelledAt == nil else { return nil }
            guard outing.creatorId != session.user.id else { return nil }
            return ReceivedOutingRow(outing: outing, participant: participant)
        }
    }

    func sentOutings(session: AuthSession) async throws -> [SentOutingRow] {
        let outings: [Outing] = try await request(
            path: "/rest/v1/outings",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "creator_id", value: "eq.\(session.user.id)"),
                .init(name: "cancelled_at", value: "is.null"),
                .init(name: "order", value: "starts_at.asc")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        guard !outings.isEmpty else { return [] }

        let participants: [OutingParticipant] = try await request(
            path: "/rest/v1/outing_participants",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "outing_id", value: "in.(\(outings.map(\.id).joined(separator: ",")))")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        let profilesById = try await profiles(session: session, ids: participants.map(\.userId))
        let participantsByOuting = Dictionary(grouping: participants, by: \.outingId)

        return outings.map { outing in
            SentOutingRow(
                outing: outing,
                participants: (participantsByOuting[outing.id] ?? [])
                    .sorted { ($0.respondedAt ?? "") > ($1.respondedAt ?? "") }
                    .map { participant in
                        OutingParticipantRow(participant: participant, profile: profilesById[participant.userId])
                    }
            )
        }
    }

    func respondToOuting(session: AuthSession, outingId: String, response: OutingResponse) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/outing_participants",
            queryItems: [
                .init(name: "outing_id", value: "eq.\(outingId)"),
                .init(name: "user_id", value: "eq.\(session.user.id)")
            ],
            method: "PATCH",
            session: session,
            body: UpdateOutingResponsePayload(
                response: response.rawValue,
                responded_at: response == .pending ? nil : DateHelpers.iso(Date())
            )
        )
    }

    func createOuting(
        session: AuthSession,
        title: String,
        startsAt: Date,
        endsAt: Date,
        location: String?,
        note: String?,
        friendIds: [String]
    ) async throws {
        try await createOuting(
            session: session,
            title: title,
            startsAt: startsAt,
            endsAt: endsAt,
            location: location,
            note: note,
            friendIds: friendIds,
            groupId: nil
        )
    }

    func createOuting(
        session: AuthSession,
        title: String,
        startsAt: Date,
        endsAt: Date,
        location: String?,
        note: String?,
        friendIds: [String],
        groupId: String?
    ) async throws {
        let outing: [CreatedOuting] = try await request(
            path: "/rest/v1/outings",
            queryItems: [.init(name: "select", value: "id")],
            method: "POST",
            session: session,
            body: NewOutingPayload(
                creator_id: session.user.id,
                group_id: groupId,
                title: title,
                starts_at: DateHelpers.iso(startsAt),
                ends_at: DateHelpers.iso(endsAt),
                location: location,
                note: note
            )
        )
        guard let outingId = outing.first?.id else { return }

        let uniqueFriendIds = Array(Set(friendIds)).filter { $0 != session.user.id }
        let participantRows = [NewOutingParticipantPayload(
            outing_id: outingId,
            user_id: session.user.id,
            response: OutingResponse.accepted.rawValue,
            responded_at: DateHelpers.iso(Date())
        )] + uniqueFriendIds.map { friendId in
            NewOutingParticipantPayload(
                outing_id: outingId,
                user_id: friendId,
                response: OutingResponse.pending.rawValue,
                responded_at: nil
            )
        }
        _ = try await rawRequest(
            path: "/rest/v1/outing_participants",
            method: "POST",
            session: session,
            body: participantRows
        )
    }

    func setOutingConfirmed(session: AuthSession, outingId: String, confirmed: Bool) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/outings",
            queryItems: [
                .init(name: "id", value: "eq.\(outingId)"),
                .init(name: "creator_id", value: "eq.\(session.user.id)")
            ],
            method: "PATCH",
            session: session,
            body: UpdateOutingConfirmationPayload(confirmed_at: confirmed ? DateHelpers.iso(Date()) : nil)
        )
    }

    /// Renvoie les 200 messages les plus recents, dans l'ordre chronologique.
    /// La retention courte (1 a 7 jours apres la sortie) borne naturellement le
    /// volume ; ce plafond evite surtout de re-telecharger un historique qui
    /// grossirait sans limite sur une sortie tres bavarde.
    func outingMessages(session: AuthSession, outingId: String) async throws -> [OutingMessage] {
        let rows: [OutingMessage] = try await request(
            path: "/rest/v1/outing_messages",
            queryItems: [
                .init(name: "select", value: "*,profile:profiles(username,avatar_url)"),
                .init(name: "outing_id", value: "eq.\(outingId)"),
                .init(name: "order", value: "created_at.desc"),
                .init(name: "limit", value: "200")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        return Array(rows.reversed())
    }

    func sendOutingMessage(session: AuthSession, outingId: String, body: String, mentionedUserIds: [String]) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/outing_messages",
            method: "POST",
            session: session,
            body: NewOutingMessagePayload(
                outing_id: outingId,
                sender_id: session.user.id,
                body: body,
                mentioned_user_ids: Array(Set(mentionedUserIds))
            )
        )
    }

    func outingParticipantsWithProfiles(session: AuthSession, outingId: String) async throws -> [OutingParticipantRow] {
        let participants: [OutingParticipant] = try await request(
            path: "/rest/v1/outing_participants",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "outing_id", value: "eq.\(outingId)")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        let profilesById = try await profiles(session: session, ids: participants.map(\.userId))
        return participants.map { participant in
            OutingParticipantRow(participant: participant, profile: profilesById[participant.userId])
        }
    }

    /// Derniers messages (toutes sorties confondues) qui mentionnent l'utilisateur courant.
    /// Sert uniquement de base a la notification locale "tu as ete mentionne" (cf. AppDataStore) ;
    /// la RLS applique deja la fenetre de retention, donc un message expire n'y apparait plus.
    func outingMentionMessages(session: AuthSession, outingIds: [String]) async throws -> [OutingMessage] {
        guard !outingIds.isEmpty else { return [] }
        return try await request(
            path: "/rest/v1/outing_messages",
            queryItems: [
                .init(name: "select", value: "id,outing_id,sender_id,body,mentioned_user_ids,created_at,profile:profiles(username,avatar_url)"),
                .init(name: "outing_id", value: "in.(\(outingIds.joined(separator: ",")))"),
                .init(name: "mentioned_user_ids", value: "cs.{\(session.user.id)}"),
                .init(name: "order", value: "created_at.desc"),
                .init(name: "limit", value: "50")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
    }

    func remindOutingParticipant(session: AuthSession, outingId: String, userId: String) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/rpc/remind_outing_participant",
            method: "POST",
            session: session,
            body: RemindOutingParticipantPayload(p_outing_id: outingId, p_user_id: userId)
        )
    }

    func deleteAccount(session: AuthSession) async throws {
        _ = try await rawRequest(
            path: "/rest/v1/rpc/delete_own_account",
            method: "POST",
            session: session,
            body: EmptyBody()
        )
    }

    private func profiles(session: AuthSession, ids: [String]) async throws -> [String: Profile] {
        guard !ids.isEmpty else { return [:] }
        let rows: [Profile] = try await request(
            path: "/rest/v1/profiles",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "id", value: "in.(\(ids.joined(separator: ",")))")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    private func groups(session: AuthSession, ids: [String]) async throws -> [PoteGroup] {
        guard !ids.isEmpty else { return [] }
        return try await request(
            path: "/rest/v1/groups",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
                .init(name: "order", value: "created_at.desc")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
    }

    private func outings(session: AuthSession, ids: [String]) async throws -> [String: Outing] {
        guard !ids.isEmpty else { return [:] }
        let rows: [Outing] = try await request(
            path: "/rest/v1/outings",
            queryItems: [
                .init(name: "select", value: "*"),
                .init(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
                .init(name: "order", value: "starts_at.asc")
            ],
            method: "GET",
            session: session,
            body: Optional<EmptyBody>.none
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    private func rpc<Response: Decodable, Body: Encodable>(
        session: AuthSession,
        name: String,
        body: Body
    ) async throws -> Response {
        try await request(path: "/rest/v1/rpc/\(name)", method: "POST", session: session, body: body)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        session: AuthSession?,
        body: Body?
    ) async throws -> Response {
        let data = try await rawRequest(path: path, queryItems: queryItems, method: method, session: session, body: body)
        return try decoder.decode(Response.self, from: data)
    }

    private func rawRequest<Body: Encodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        session: AuthSession?,
        body: Body?
    ) async throws -> Data {
        var base = config.url
        base.append(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw AppError.message("URL Supabase invalide.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if #available(iOS 14.5, *) {
            request.assumesHTTP3Capable = false
        }
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        if let session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }

        print("PoteAgenda Supabase request: \(method) \(path)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if isCancellation(error) {
                print("PoteAgenda Supabase request cancelled: \(method) \(path)")
                throw error
            }
            print("PoteAgenda Supabase transport error: \(method) \(path): \(error.localizedDescription)")
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw AppError.message("Reponse Supabase invalide.")
        }
        print("PoteAgenda Supabase response: \(http.statusCode) \(method) \(path)")
        guard (200..<300).contains(http.statusCode) else {
            let message = supabaseErrorMessage(from: data, statusCode: http.statusCode)
            print("PoteAgenda Supabase error: \(message)")
            throw AppError.message(message)
        }
        return data.isEmpty ? Data("{}".utf8) : data
    }

    private func supabaseErrorMessage(from data: Data, statusCode: Int) -> String {
        if let error = try? decoder.decode(SupabaseErrorResponse.self, from: data) {
            let code = error.code.map { " \($0)" } ?? ""
            return "Erreur Supabase \(statusCode)\(code): \(error.message)"
        }
        let body = String(data: data, encoding: .utf8)
        return body?.isEmpty == false ? body! : "Erreur Supabase \(statusCode)"
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

private struct SupabaseErrorResponse: Decodable {
    let code: String?
    let message: String
}

private struct EmptyBody: Encodable {}

private struct EmailPasswordPayload: Encodable {
    let email: String
    let password: String
}

private struct SignUpPayload: Encodable {
    let email: String
    let password: String
    let data: SignUpMetadata
}

private struct SignUpMetadata: Encodable {
    let username: String
}

private struct RefreshPayload: Encodable {
    let refresh_token: String
}

private struct NewCalendarEvent: Encodable {
    let user_id: String
    let title: String
    let start_at: String
    let end_at: String
    let color: String
    let source: String
}

private struct NewCalendarSource: Encodable {
    let user_id: String
    let label: String
    let kind: String
    let device_calendar_id: String?
}

struct CalendarEventInputPayload: Encodable {
    let title: String
    let start_at: String
    let end_at: String
    let color: String
    let external_uid: String
}

private struct ResyncCalendarSourcePayload: Encodable {
    let p_source_id: String
    let p_events: [CalendarEventInputPayload]
}

private struct NewGroupMember: Encodable {
    let group_id: String
    let user_id: String
    let role: String
}

private struct FriendsBusyEventsPayload: Encodable {
    let p_friend_ids: [String]
    let p_range_start: String
    let p_range_end: String
}

private struct UpdateOutingResponsePayload: Encodable {
    let response: String
    let responded_at: String?
}

private struct UpdateOutingConfirmationPayload: Encodable {
    let confirmed_at: String?
}

private struct RemindOutingParticipantPayload: Encodable {
    let p_outing_id: String
    let p_user_id: String
}

private struct NewOutingPayload: Encodable {
    let creator_id: String
    let group_id: String?
    let title: String
    let starts_at: String
    let ends_at: String
    let location: String?
    let note: String?
}

private struct NewOutingParticipantPayload: Encodable {
    let outing_id: String
    let user_id: String
    let response: String
    let responded_at: String?

    enum CodingKeys: String, CodingKey {
        case outing_id
        case user_id
        case response
        case responded_at
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outing_id, forKey: .outing_id)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(response, forKey: .response)
        try container.encode(responded_at, forKey: .responded_at)
    }
}

private struct CreatedOuting: Decodable {
    let id: String
}

private struct NewOutingMessagePayload: Encodable {
    let outing_id: String
    let sender_id: String
    let body: String
    let mentioned_user_ids: [String]
}

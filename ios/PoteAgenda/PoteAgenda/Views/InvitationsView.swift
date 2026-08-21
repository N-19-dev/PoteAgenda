import SwiftUI

struct InvitationsView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var selectedTab: InvitationsTab = .received

    var body: some View {
        NavigationStack {
            List {
                Picker("Invitations", selection: $selectedTab) {
                    ForEach(InvitationsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))

                switch selectedTab {
                case .received:
                    ReceivedInvitationsSection(outings: dataStore.outings)
                case .sent:
                    SentInvitationsSection(outings: dataStore.sentOutings)
                }
            }
            .navigationTitle("Invitations")
            .refreshable { await dataStore.refreshOutings() }
            .task { await dataStore.refreshOutings() }
        }
    }
}

private enum InvitationsTab: String, CaseIterable, Identifiable {
    case received
    case sent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .received: "Recues"
        case .sent: "Envoyees"
        }
    }
}

private struct ReceivedInvitationsSection: View {
    let outings: [ReceivedOutingRow]

    var body: some View {
        if outings.isEmpty {
            EmptyStateView(title: "Aucune invitation reçue", systemImage: "envelope.open")
        } else {
            ForEach(outings) { row in
                NavigationLink {
                    ReceivedInvitationDetailView(row: row)
                } label: {
                    InvitationSummaryView(
                        outing: row.outing,
                        status: row.response.label,
                        statusStyle: row.response.statusStyle,
                        isReminded: row.response == .pending && recentlyReminded(row.participant.remindedAt)
                    )
                }
            }
        }
    }
}

private struct SentInvitationsSection: View {
    let outings: [SentOutingRow]

    var body: some View {
        if outings.isEmpty {
            EmptyStateView(title: "Aucune invitation envoyée", systemImage: "paperplane")
        } else {
            ForEach(outings) { row in
                NavigationLink {
                    SentInvitationDetailView(row: row)
                } label: {
                    InvitationSummaryView(
                        outing: row.outing,
                        status: row.summary,
                        statusStyle: row.outing.confirmedAt == nil ? .neutral : .accepted
                    )
                }
            }
        }
    }
}

private struct InvitationSummaryView: View {
    let outing: Outing
    let status: String
    let statusStyle: ResponseStatusStyle
    var isReminded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(outing.title)
                        .font(.headline)
                    InvitationDateText(outing: outing)
                }
                Spacer()
                ResponseBadge(title: status, style: statusStyle)
            }

            if let location = outing.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isReminded {
                Label("On te relance pour cette sortie", systemImage: "bell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReceivedInvitationDetailView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    let row: ReceivedOutingRow

    var body: some View {
        List {
            Section {
                InvitationHeaderView(outing: row.outing, status: row.response.label, statusStyle: row.response.statusStyle)
            }

            InvitationInfoSection(outing: row.outing)

            if row.response == .pending, recentlyReminded(row.participant.remindedAt) {
                Section {
                    Label("On te relance pour cette sortie", systemImage: "bell.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Reponse") {
                ResponseActionButton(title: "Accepter", systemImage: "checkmark.circle.fill", role: nil) {
                    Task { await dataStore.respondToOuting(row.outing, response: .accepted) }
                }
                ResponseActionButton(title: "Refuser", systemImage: "xmark.circle.fill", role: .destructive) {
                    Task { await dataStore.respondToOuting(row.outing, response: .declined) }
                }
                ResponseActionButton(title: "Remettre en attente", systemImage: "clock.arrow.circlepath", role: nil) {
                    Task { await dataStore.respondToOuting(row.outing, response: .pending) }
                }
                .disabled(row.response == .pending)
            }

            if canDiscussOuting(row.outing) {
                OutingDiscussionSection(outing: row.outing)
            }
        }
        .navigationTitle("Invitation")
        .poteInlineNavigationTitle()
    }
}

private struct SentInvitationDetailView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    let row: SentOutingRow

    var body: some View {
        List {
            Section {
                InvitationHeaderView(
                    outing: row.outing,
                    status: row.outing.confirmedAt == nil ? "Non confirmé" : "Confirmé",
                    statusStyle: row.outing.confirmedAt == nil ? .neutral : .accepted
                )
            }

            InvitationInfoSection(outing: row.outing)

            Section("Participants") {
                ForEach(row.participants) { participantRow in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: participantRow.participant.response.systemImage)
                                .foregroundStyle(participantRow.participant.response.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(participantRow.profile?.username ?? "Participant")
                                    .font(.headline)
                                Text(participantRow.profile?.email ?? participantRow.participant.userId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ResponseBadge(
                                title: participantRow.participant.response.label,
                                style: participantRow.participant.response.statusStyle
                            )
                        }

                        if participantRow.participant.response == .pending {
                            Button {
                                Task {
                                    await dataStore.remindOutingParticipant(
                                        outing: row.outing,
                                        participant: participantRow.participant
                                    )
                                }
                            } label: {
                                Label(
                                    recentlyReminded(participantRow.participant.remindedAt) ? "Relance envoyée" : "Relancer",
                                    systemImage: "bell"
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .disabled(dataStore.isLoading || recentlyReminded(participantRow.participant.remindedAt))
                        }
                    }
                }
            }

            Section("Decision") {
                Button {
                    Task { await dataStore.setOutingConfirmed(row.outing, confirmed: row.outing.confirmedAt == nil) }
                } label: {
                    Label(
                        row.outing.confirmedAt == nil ? "Confirmer le rendez-vous" : "Annuler la confirmation",
                        systemImage: row.outing.confirmedAt == nil ? "checkmark.seal.fill" : "arrow.uturn.backward.circle"
                    )
                }
            }

            if canDiscussOuting(row.outing) {
                OutingDiscussionSection(outing: row.outing)
            }
        }
        .navigationTitle("Invitation envoyée")
        .poteInlineNavigationTitle()
    }
}

private struct InvitationHeaderView: View {
    let outing: Outing
    let status: String
    let statusStyle: ResponseStatusStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(outing.title)
                    .font(.title2.weight(.bold))
                Spacer()
                ResponseBadge(title: status, style: statusStyle)
            }
            InvitationDateText(outing: outing)
        }
        .padding(.vertical, 4)
    }
}

private struct InvitationInfoSection: View {
    let outing: Outing

    var body: some View {
        Section("Détails") {
            Label {
                InvitationDateText(outing: outing)
            } icon: {
                Image(systemName: "calendar")
            }

            if let location = outing.location, !location.isEmpty {
                LocationLink(location: location)
            }

            if let note = outing.note, !note.isEmpty {
                Label(note, systemImage: "note.text")
            }
        }
    }
}

private struct InvitationDateText: View {
    let outing: Outing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateText)
                .font(.subheadline.weight(.semibold))
            EventTimeText(start: outing.startsAt, end: outing.endsAt)
        }
    }

    private var dateText: String {
        guard let date = DateHelpers.parse(outing.startsAt) else { return outing.startsAt }
        return DateHelpers.displayDateString(date)
    }
}

private struct ResponseActionButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct ResponseBadge: View {
    let title: String
    let style: ResponseStatusStyle

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(style.foreground)
            .background(style.background, in: Capsule())
    }
}

private enum ResponseStatusStyle {
    case pending
    case accepted
    case declined
    case neutral

    var foreground: Color {
        switch self {
        case .pending: .orange
        case .accepted: .green
        case .declined: .red
        case .neutral: .secondary
        }
    }

    var background: Color {
        foreground.opacity(0.14)
    }
}

private let remindCooldownSeconds: TimeInterval = 12 * 60 * 60

private func recentlyReminded(_ remindedAt: String?) -> Bool {
    guard let remindedAt, let date = DateHelpers.parse(remindedAt) else { return false }
    return Date().timeIntervalSince(date) < remindCooldownSeconds
}

private extension OutingResponse {
    var label: String {
        switch self {
        case .pending: "En attente"
        case .accepted: "Acceptee"
        case .declined: "Refusee"
        }
    }

    var statusStyle: ResponseStatusStyle {
        switch self {
        case .pending: .pending
        case .accepted: .accepted
        case .declined: .declined
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "clock.fill"
        case .accepted: "checkmark.circle.fill"
        case .declined: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .orange
        case .accepted: .green
        case .declined: .red
        }
    }
}

private extension SentOutingRow {
    var summary: String {
        let invited = participants.count
        let accepted = participants.filter { $0.participant.response == .accepted }.count
        let pending = participants.filter { $0.participant.response == .pending }.count
        return "\(accepted)/\(invited) acceptés, \(pending) attente"
    }
}

private extension View {
    @ViewBuilder
    func poteInlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

func canDiscussOuting(_ outing: Outing) -> Bool {
    guard outing.cancelledAt == nil, let ends = DateHelpers.parse(outing.endsAt) else { return false }
    let expiresAt = ends.addingTimeInterval(TimeInterval(outing.messageRetentionDays) * 86_400)
    return Date() <= expiresAt
}

struct OutingDiscussionSection: View {
    @EnvironmentObject private var dataStore: AppDataStore
    let outing: Outing

    @State private var messages: [OutingMessage] = []
    @State private var participants: [OutingParticipantRow] = []
    @State private var isLoaded = false
    @State private var newMessage = ""
    @State private var mentionedIds = Set<String>()
    @State private var isSending = false
    @State private var loadError: String?

    private var mentionUsernames: Set<String> {
        Set(participants.compactMap(\.profile?.username))
    }

    private var taggableParticipants: [OutingParticipantRow] {
        participants.filter { $0.participant.userId != dataStore.currentUserId && $0.profile != nil }
    }

    /// Le texte tape apres le dernier "@" du message, tant qu'aucun espace ne
    /// l'interrompt et que le "@" est bien en debut de mot (pas au milieu d'un
    /// email par ex.). `nil` tant que l'utilisateur n'a pas tape "@".
    private var mentionQuery: String? {
        guard let atIndex = newMessage.lastIndex(of: "@") else { return nil }
        let afterAt = newMessage[newMessage.index(after: atIndex)...]
        guard !afterAt.contains(where: \.isWhitespace) else { return nil }
        if atIndex != newMessage.startIndex {
            let beforeAt = newMessage[newMessage.index(before: atIndex)]
            guard beforeAt.isWhitespace else { return nil }
        }
        return String(afterAt)
    }

    private var mentionSuggestions: [OutingParticipantRow] {
        guard let query = mentionQuery else { return [] }
        let filtered = taggableParticipants.filter { row in
            guard let username = row.profile?.username else { return false }
            return query.isEmpty || username.lowercased().hasPrefix(query.lowercased())
        }
        return Array(filtered.prefix(5))
    }

    var body: some View {
        Section("Discussion") {
            VStack(alignment: .leading, spacing: 10) {
                if !isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if messages.isEmpty {
                    Text("Aucun message pour l'instant — lance la discussion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(messages) { message in
                                    OutingMessageBubble(
                                        message: message,
                                        isMine: message.senderId == dataStore.currentUserId,
                                        mentionUsernames: mentionUsernames
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        .frame(height: 240)
                        .onAppear { scrollToBottom(proxy) }
                        .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                    }
                }

                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !mentionSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(mentionSuggestions, id: \.id) { row in
                                Button {
                                    selectMention(row)
                                } label: {
                                    Text("@\(row.profile?.username ?? "")")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Écrire un message…", text: $newMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(isSending || newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.vertical, 4)
        }
        .task { await load() }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = messages.last?.id else { return }
        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
    }

    private func selectMention(_ row: OutingParticipantRow) {
        guard let username = row.profile?.username, let atIndex = newMessage.lastIndex(of: "@") else { return }
        newMessage.replaceSubrange(atIndex..., with: "@\(username) ")
        mentionedIds.insert(row.participant.userId)
    }

    private func load() async {
        async let messagesTask = dataStore.outingMessages(outingId: outing.id)
        async let participantsTask = dataStore.outingParticipants(outingId: outing.id)
        do {
            messages = try await messagesTask
            loadError = nil
        } catch {
            loadError = "Impossible de charger la discussion."
        }
        participants = (try? await participantsTask) ?? []
        isLoaded = true
    }

    private func send() {
        let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        Task {
            do {
                try await dataStore.sendOutingMessage(outingId: outing.id, body: trimmed, mentionedUserIds: Array(mentionedIds))
                newMessage = ""
                mentionedIds.removeAll()
                messages = try await dataStore.outingMessages(outingId: outing.id)
                loadError = nil
            } catch {
                loadError = "Impossible d'envoyer le message."
            }
            isSending = false
        }
    }
}

struct OutingMessageBubble: View {
    let message: OutingMessage
    let isMine: Bool
    var mentionUsernames: Set<String> = []

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 2) {
                if !isMine {
                    Text(message.profile?.username ?? "Membre")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(highlightedBody)
                    .font(.subheadline)
                Text(DateHelpers.displayDateTimeString(message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isMine ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
            if !isMine { Spacer(minLength: 24) }
        }
    }

    private var highlightedBody: AttributedString {
        var attributed = AttributedString(message.body)
        guard !mentionUsernames.isEmpty else { return attributed }
        let nsBody = message.body as NSString
        for username in mentionUsernames.sorted(by: { $0.count > $1.count }) {
            let token = "@\(username)"
            var searchStart = 0
            while searchStart < nsBody.length {
                let searchRange = NSRange(location: searchStart, length: nsBody.length - searchStart)
                let found = nsBody.range(of: token, options: [], range: searchRange)
                if found.location == NSNotFound { break }
                if let range = Range(found, in: message.body), let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .accentColor
                    attributed[attrRange].font = .subheadline.weight(.semibold)
                }
                searchStart = found.location + found.length
            }
        }
        return attributed
    }
}

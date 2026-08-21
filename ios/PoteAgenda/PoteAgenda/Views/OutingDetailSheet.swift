import SwiftUI

/// Liste les blocs d'un même créneau chevauchant (vue semaine/mois, tap sur
/// le badge de compte) ; sélectionner une ligne ouvre son détail habituel.
struct AgendaOverlapGroupSheet: View {
    let blocks: [AgendaBlock]
    let onSelect: (AgendaBlock) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List(blocks) { block in
                Button {
                    onSelect(block)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(block.style.backgroundColor(for: block))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let subtitle = block.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(block.timeLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Ce créneau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { onClose() }
                }
            }
        }
    }
}

struct AgendaBlockDetailSheet: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var locallyRemindedParticipantIds = Set<String>()
    @State private var receivedParticipants: [OutingParticipantRow] = []
    @State private var showingCancelConfirmation = false
    let block: AgendaBlock
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(headerDotColor)
                                .frame(width: 12, height: 12)
                                .overlay {
                                    if block.style == .friendBusy {
                                        Circle().stroke(Color.secondary.opacity(0.55), lineWidth: 1)
                                    } else if block.style == .friendPending {
                                        Circle().stroke(Color(hex: "#f97316").opacity(0.75), lineWidth: 1)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(headerTitle)
                                    .font(.headline.weight(.bold))
                                if let subtitle = headerSubtitle {
                                    Text(subtitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text(block.dateRangeLabel)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                detailSections
                actionSections
                discussionSection
            }
            .navigationTitle("Détail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismissSheet()
                    }
                }
            }
        }
        .task(id: block.id) {
            await loadReceivedParticipantsIfNeeded()
        }
        .confirmationDialog(
            "Supprimer cette invitation ?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                guard case .sentOuting(let row) = block.details else { return }
                Task {
                    await dataStore.cancelOuting(row.outing)
                    dismissSheet()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les participants ne verront plus cette invitation et la discussion associée sera fermée.")
        }
    }

    private func loadReceivedParticipantsIfNeeded() async {
        guard case .receivedOuting(let row) = block.details else { return }
        receivedParticipants = (try? await dataStore.outingParticipants(outingId: row.outing.id)) ?? []
    }

    private func organizerName(for row: ReceivedOutingRow) -> String? {
        receivedParticipants.first { $0.participant.userId == row.outing.creatorId }?.profile?.username
    }

    private func participantDisplayName(_ participant: OutingParticipantRow, creatorId: String) -> String {
        let name = participant.profile?.username ?? "Invité"
        return participant.participant.userId == creatorId ? "\(name) (organisateur)" : name
    }

    private var headerTitle: String {
        switch block.details {
        case .friendBusy(_, let friendName, _):
            return "\(friendName) pas dispo"
        case .friendPending(_, let friendName):
            return "\(friendName) sollicité(e)"
        default:
            return block.title
        }
    }

    private var headerSubtitle: String? {
        switch block.details {
        case .friendBusy, .friendPending:
            return nil
        default:
            return block.subtitle
        }
    }

    private var headerDotColor: Color {
        switch block.style {
        case .friendBusy:
            return Color.poteBusyOther
        case .friendPending:
            return Color(hex: "#f97316")
        case .ownBusy, .outing:
            return Color(hex: block.color)
        }
    }

    @ViewBuilder
    private var detailSections: some View {
        switch block.details {
        case .ownEvent(let event):
            Section("Indisponibilité") {
                DetailRow(label: "Titre", value: event.title)
                DetailRow(label: "Source", value: event.source)
            }
        case .receivedOuting(let row):
            Section("Invitation") {
                DetailRow(label: "Statut", value: row.response.agendaLabel)
                if let organizerName = organizerName(for: row) {
                    DetailRow(label: "Invité par", value: organizerName)
                }
                if let remindedAt = row.participant.remindedAt, row.response == .pending {
                    DetailRow(label: "Relance", value: DateHelpers.displayDateTimeString(remindedAt))
                }
                if let location = row.outing.location, !location.isEmpty {
                    DetailLocationRow(location: location)
                }
                if let note = row.outing.note, !note.isEmpty {
                    DetailRow(label: "Note", value: note)
                }
            }
            if !receivedParticipants.isEmpty {
                Section("Participants") {
                    ForEach(receivedParticipants) { participant in
                        HStack {
                            Text(participantDisplayName(participant, creatorId: row.outing.creatorId))
                            Spacer()
                            Text(participant.participant.response.agendaLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: participant.participant.response.agendaColor))
                        }
                    }
                }
            }
        case .sentOuting(let row):
            Section("Invitation envoyée") {
                DetailRow(label: "Statut", value: row.outing.confirmedAt == nil ? "En attente" : "Confirmée")
                if let location = row.outing.location, !location.isEmpty {
                    DetailLocationRow(location: location)
                }
                if let note = row.outing.note, !note.isEmpty {
                    DetailRow(label: "Note", value: note)
                }
            }
            Section("Participants") {
                let pendingParticipants = pendingParticipants(in: row)
                if pendingParticipants.count > 1 {
                    Button {
                        Task {
                            let didRemind = await dataStore.remindPendingOutingParticipants(
                                outing: row.outing,
                                participants: pendingParticipants.map(\.participant)
                            )
                            if didRemind {
                                locallyRemindedParticipantIds.formUnion(pendingParticipants.map(\.participant.userId))
                            }
                        }
                    } label: {
                        Label("Relancer tous", systemImage: "bell.badge")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(dataStore.isLoading || pendingParticipants.allSatisfy { isReminded($0) })
                }

                ForEach(row.participants) { participant in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(participant.profile?.username ?? "Invité")
                            Spacer()
                            Text(participant.participant.response.agendaLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: participant.participant.response.agendaColor))
                        }

                        if participant.participant.response == .pending {
                            Button {
                                Task {
                                    let didRemind = await dataStore.remindOutingParticipant(
                                        outing: row.outing,
                                        participant: participant.participant
                                    )
                                    if didRemind {
                                        locallyRemindedParticipantIds.insert(participant.participant.userId)
                                    }
                                }
                            } label: {
                                Label(
                                    isReminded(participant) ? "Relance envoyée" : "Relancer",
                                    systemImage: "bell"
                                )
                                .font(.caption.weight(.semibold))
                            }
                            .disabled(dataStore.isLoading || isReminded(participant))
                        }
                    }
                }
            }
        case .friendBusy(let busyEvent, let friendName, let source):
            Section("\(friendName) pas dispo") {
                DetailRow(label: "Personne", value: friendName)
                DetailRow(label: "Quand", value: block.dateRangeLabel)
                DetailRow(label: "Via", value: source)
                if let title = busyEvent.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DetailRow(label: "Ce qu'il fait", value: title)
                } else {
                    DetailRow(label: "Ce qu'il fait", value: "Détail non partagé")
                }
            }
        case .friendPending(_, let friendName):
            Section("\(friendName) sollicité(e)") {
                DetailRow(label: "Personne", value: friendName)
                DetailRow(label: "Quand", value: block.dateRangeLabel)
                DetailRow(label: "Statut", value: "Sollicité(e)")
                Text("Pas encore indisponible : si \(friendName) confirme, ce créneau deviendra occupé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .generic:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionSections: some View {
        switch block.details {
        case .ownEvent(let event):
            Section {
                Button("Supprimer l'indisponibilité", role: .destructive) {
                    Task {
                        await dataStore.deleteEvent(event)
                        dismissSheet()
                    }
                }
            }
        case .receivedOuting(let row):
            Section("Réponse") {
                Button("Accepter") {
                    Task {
                        await dataStore.respondToOuting(row.outing, response: .accepted)
                        dismissSheet()
                    }
                }
                .disabled(row.response == .accepted)

                Button("Refuser", role: .destructive) {
                    Task {
                        await dataStore.respondToOuting(row.outing, response: .declined)
                        dismissSheet()
                    }
                }
                .disabled(row.response == .declined)

                Button("Remettre en attente") {
                    Task {
                        await dataStore.respondToOuting(row.outing, response: .pending)
                        dismissSheet()
                    }
                }
                .disabled(row.response == .pending)
            }
        case .sentOuting:
            Section {
                Button("Supprimer l'invitation", role: .destructive) {
                    showingCancelConfirmation = true
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var discussionSection: some View {
        switch block.details {
        case .receivedOuting(let row) where canDiscussOuting(row.outing):
            OutingDiscussionSection(outing: row.outing)
        case .sentOuting(let row) where canDiscussOuting(row.outing):
            OutingDiscussionSection(outing: row.outing)
        default:
            EmptyView()
        }
    }

    private func dismissSheet() {
        onClose()
        dismiss()
    }

    private func pendingParticipants(in row: SentOutingRow) -> [OutingParticipantRow] {
        row.participants.filter { $0.participant.response == .pending }
    }

    private func isReminded(_ participant: OutingParticipantRow) -> Bool {
        locallyRemindedParticipantIds.contains(participant.participant.userId)
            || agendaRecentlyReminded(participant.participant.remindedAt)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct DetailLocationRow: View {
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Lieu")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            LocationLink(location: location)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}

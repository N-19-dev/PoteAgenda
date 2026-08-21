import EventKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var dataStore: AppDataStore
    @ObservedObject private var locationService = LocationService.shared
    @State private var showDeleteConfirmation = false
    @State private var pendingCalendar: EKCalendar?
    @State private var pendingCalendarEventCount = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Compte") {
                    Text(sessionStore.session?.user.email ?? "Connecté")
                    Button("Se déconnecter", role: .destructive) {
                        Task { await sessionStore.signOut() }
                    }
                    Button("Supprimer mon compte", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }

                connectedCalendarsSection

                Section {
                    Text("PoteAgenda peut utiliser ta position pour estimer le temps de trajet jusqu'au lieu d'une sortie et te prévenir 15 minutes avant l'heure à laquelle il faut partir. Elle n'est jamais partagée avec tes amis ni stockée sur le serveur, uniquement utilisée sur ton appareil au moment du calcul.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Utiliser ma position pour les rappels de départ", isOn: $dataStore.departureRemindersEnabled)

                    if dataStore.departureRemindersEnabled {
                        locationAuthorizationRow

                        Picker("Mode de trajet", selection: $dataStore.travelMode) {
                            ForEach(TravelMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                    }
                } header: {
                    Text("Trajets")
                }

                Section {
                    Toggle("Masquer le contenu des notifications", isOn: $dataStore.hideNotificationContent)
                    Text("Sur l'écran verrouillé, les notifications n'affichent ni titre de sortie, ni nom d'expéditeur, ni contenu de message tant que tu n'as pas ouvert l'app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Notifications")
                }

                Section("Backend") {
                    Text("Supabase + RLS")
                    Text("Les amis et groupes ne récupèrent que les créneaux autorisés par les politiques existantes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Compte")
            .task {
                dataStore.loadDeviceCalendarsIfAuthorized()
                await dataStore.refreshCalendarSources()
            }
            .confirmationDialog(
                "Supprimer définitivement ton compte ?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Supprimer mon compte", role: .destructive) {
                    Task { await sessionStore.deleteAccount() }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Toutes tes données (agenda, amis, groupes, sorties) seront supprimées. Cette action est irréversible.")
            }
            .confirmationDialog(
                "Importer ce calendrier ?",
                isPresented: Binding(
                    get: { pendingCalendar != nil },
                    set: { if !$0 { pendingCalendar = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Importer \(pendingCalendarEventCount) événement\(pendingCalendarEventCount > 1 ? "s" : "")") {
                    if let calendar = pendingCalendar {
                        Task { await dataStore.connectDeviceCalendar(calendar) }
                    }
                    pendingCalendar = nil
                }
                Button("Annuler", role: .cancel) { pendingCalendar = nil }
            } message: {
                Text(pendingCalendarSummary)
            }
        }
    }

    private var pendingCalendarSummary: String {
        let horizon = EventKitService.horizonDays
        let titlePart = dataStore.importRealEventTitles
            ? "avec leur titre réel (import des titres activé dans les réglages)"
            : "uniquement comme \"Occupé\", sans titre"
        return "\(pendingCalendarEventCount) événement\(pendingCalendarEventCount > 1 ? "s" : "") des \(horizon) prochains jours seront envoyés au serveur, \(titlePart)."
    }

    @ViewBuilder
    private var connectedCalendarsSection: some View {
        Section {
            ForEach(dataStore.calendarSources) { source in
                CalendarSourceRow(source: source)
            }

            Toggle("Importer le vrai titre de mes événements", isOn: $dataStore.importRealEventTitles)

            switch dataStore.deviceCalendarAuthorizationStatus {
            case .fullAccess:
                if availableDeviceCalendars.isEmpty {
                    Text("Aucun calendrier disponible sur cet appareil.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(availableDeviceCalendars, id: \.calendarIdentifier) { calendar in
                            Button(calendar.title) {
                                pendingCalendarEventCount = dataStore.upcomingEventCount(for: calendar)
                                pendingCalendar = calendar
                            }
                        }
                    } label: {
                        Label("Connecter un calendrier", systemImage: "calendar.badge.plus")
                    }
                }
            case .denied, .restricted:
                Text("Accès refusé. Autorise PoteAgenda dans Réglages > Confidentialité > Calendriers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                Button {
                    Task { await dataStore.requestDeviceCalendarAccess() }
                } label: {
                    Label("Connecter mon calendrier iOS", systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text("Calendriers connectés")
        } footer: {
            Text("Par défaut, seuls tes créneaux \"Occupé\" sont envoyés au serveur (jamais le vrai titre). Si tu actives l'import des titres réels, ils sont stockés côté serveur mais restent invisibles pour tes amis et groupes, sauf partage explicite.")
        }
    }

    @ViewBuilder
    private var locationAuthorizationRow: some View {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            Label("Position autorisée", systemImage: "location.fill")
                .foregroundStyle(.secondary)
        case .denied, .restricted:
            Text("Position refusée. Autorise PoteAgenda dans Réglages > Confidentialité > Position pour activer les rappels de départ.")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            Button {
                locationService.requestAuthorizationIfNeeded()
            } label: {
                Label("Autoriser la position", systemImage: "location")
            }
        }
    }

    private var availableDeviceCalendars: [EKCalendar] {
        let connectedIds = Set(dataStore.calendarSources.compactMap(\.deviceCalendarId))
        return dataStore.deviceCalendars.filter { !connectedIds.contains($0.calendarIdentifier) }
    }
}

private struct CalendarSourceRow: View {
    @EnvironmentObject private var dataStore: AppDataStore
    let source: CalendarSource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(source.label)
                Spacer()
                if source.kind == "device" {
                    Button {
                        Task { await dataStore.resyncDeviceCalendarSource(source) }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                }
                Button(role: .destructive) {
                    Task { await dataStore.deleteCalendarSource(source) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Text(lastSyncedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var lastSyncedLabel: String {
        guard let lastSyncedAt = source.lastSyncedAt else { return "Jamais synchronisé" }
        return "Synchronisé le \(DateHelpers.displayDateTimeString(lastSyncedAt))"
    }
}

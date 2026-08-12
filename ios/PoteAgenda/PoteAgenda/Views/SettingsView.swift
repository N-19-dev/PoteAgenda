import EventKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var dataStore: AppDataStore

    var body: some View {
        NavigationStack {
            List {
                Section("Compte") {
                    Text(sessionStore.session?.user.email ?? "Connecte")
                    Button("Se deconnecter", role: .destructive) {
                        Task { await sessionStore.signOut() }
                    }
                }

                connectedCalendarsSection

                Section("Backend") {
                    Text("Supabase + RLS")
                    Text("Les amis et groupes ne recuperent que les creneaux autorises par les politiques existantes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Compte")
            .task {
                dataStore.loadDeviceCalendarsIfAuthorized()
                await dataStore.refreshCalendarSources()
            }
        }
    }

    @ViewBuilder
    private var connectedCalendarsSection: some View {
        Section {
            ForEach(dataStore.calendarSources) { source in
                CalendarSourceRow(source: source)
            }

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
                                Task { await dataStore.connectDeviceCalendar(calendar) }
                            }
                        }
                    } label: {
                        Label("Connecter un calendrier", systemImage: "calendar.badge.plus")
                    }
                }
            case .denied, .restricted:
                Text("Acces refuse. Autorise PoteAgenda dans Reglages > Confidentialite > Calendriers.")
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
            Text("Calendriers connectes")
        } footer: {
            Text("Les evenements importes restent prives : seuls tes creneaux occupes/libres sont visibles par tes amis et groupes, jamais leur titre (sauf partage explicite).")
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
        guard let lastSyncedAt = source.lastSyncedAt else { return "Jamais synchronise" }
        return "Synchronise le \(DateHelpers.displayDateTimeString(lastSyncedAt))"
    }
}

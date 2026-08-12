import SwiftUI

struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
    }
}

struct EventTimeText: View {
    let start: String
    let end: String

    var body: some View {
        Text("\(time(start)) - \(time(end))")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func time(_ value: String) -> String {
        guard let date = DateHelpers.parse(value) else { return value }
        return DateHelpers.displayTimeString(date)
    }
}

extension View {
    @ViewBuilder
    func poteUsernameInputTraits() -> some View {
        #if os(iOS)
        self.textContentType(.username)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func poteEmailInputTraits() -> some View {
        #if os(iOS)
        self.keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func potePasswordInputTraits(isNewPassword: Bool) -> some View {
        #if os(iOS)
        self.textContentType(isNewPassword ? .newPassword : .password)
        #else
        self
        #endif
    }

    @ViewBuilder
    func poteSearchInputTraits() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var poteTopBarTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

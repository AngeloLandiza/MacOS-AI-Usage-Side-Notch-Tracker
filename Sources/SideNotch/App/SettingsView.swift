import SwiftUI

/// Tabbed settings: notch behavior in General, all provider authentication in
/// Providers. API keys live in the login Keychain; Claude/Codex reuse their
/// CLIs' logins.
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ProvidersTab(store: store)
                .tabItem { Label("Providers", systemImage: "person.badge.key") }
        }
        .frame(width: 460)
        .fixedSize()
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Automatically hide the notch", isOn: $settings.autoHide)
                Text("Tucks the notch away to a thin strip at the screen edge; move the pointer over it to bring it back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Size") {
                    Slider(value: $settings.scale, in: AppSettings.scaleRange) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "circle").font(.system(size: 8))
                    } maximumValueLabel: {
                        Image(systemName: "circle").font(.system(size: 14))
                    }
                    .frame(width: 220)
                }
                Text("Changes apply immediately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProvidersTab: View {
    @ObservedObject var store: UsageStore
    @State private var openRouterKey = Keychain.read(service: OpenRouterProvider.keychainService) ?? ""
    @State private var deepSeekKey = Keychain.read(service: DeepSeekProvider.keychainService) ?? ""
    @State private var saveError: String?

    var body: some View {
        Form {
            Section {
                connectionRow(
                    name: "Claude",
                    connected: ClaudeProvider().isConfigured(),
                    stateID: "claude",
                    help: "Uses your Claude Code login. To connect, run `claude` in Terminal and sign in."
                )
                connectionRow(
                    name: "OpenAI",
                    connected: CodexProvider().isConfigured(),
                    stateID: "openai",
                    help: "Uses your Codex CLI login. To connect, run `codex login` in Terminal."
                )
            } header: {
                Text("Signed in automatically")
            }

            Section {
                keyRow(
                    name: "OpenRouter",
                    key: $openRouterKey,
                    stateID: "openrouter",
                    help: "Create a key at openrouter.ai/keys",
                    url: "https://openrouter.ai/keys"
                )
                keyRow(
                    name: "DeepSeek",
                    key: $deepSeekKey,
                    stateID: "deepseek",
                    help: "Create a key at platform.deepseek.com/api_keys",
                    url: "https://platform.deepseek.com/api_keys"
                )
            } header: {
                Text("API keys")
            } footer: {
                Text("Keys are stored in your login Keychain and only ever sent to their own provider.")
            }

            LabeledContent {
                Button("Save & Test") { save() }
            } label: {
                if let saveError {
                    Text(saveError).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        let savedOpenRouter = Keychain.write(service: OpenRouterProvider.keychainService, value: openRouterKey.trimmed)
        let savedDeepSeek = Keychain.write(service: DeepSeekProvider.keychainService, value: deepSeekKey.trimmed)
        saveError = savedOpenRouter && savedDeepSeek
            ? nil : "Couldn't save to the Keychain — the previous keys are unchanged."
        store.reloadProviders()
        Task {
            // Retest drops last-good state so a bad replacement key surfaces
            // immediately; the plain refresh picks up newly added providers.
            await store.retest(ids: ["openrouter", "deepseek"])
            await store.refreshAll()
        }
    }

    private func connectionRow(name: String, connected: Bool, stateID: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                statusBadge(connected: connected, stateID: stateID)
            }
            Text(help)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func keyRow(name: String, key: Binding<String>, stateID: String, help: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                // Reflects the *saved* key, not unsaved field edits.
                statusBadge(connected: store.providers.contains { $0.id == stateID }, stateID: stateID)
            }
            SecureField("API key", text: key)
                .textFieldStyle(.roundedBorder)
            if let link = URL(string: url) {
                Link(help, destination: link)
                    .font(.callout)
            }
        }
    }

    /// "Connected" plus the latest fetch outcome so a bad key is visible here.
    @ViewBuilder
    private func statusBadge(connected: Bool, stateID: String) -> some View {
        switch (connected, store.states[stateID]) {
        case (false, _):
            Label("Not connected", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case (true, .failed):
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case (true, .ok):
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case (true, _):
            Label("Checking…", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

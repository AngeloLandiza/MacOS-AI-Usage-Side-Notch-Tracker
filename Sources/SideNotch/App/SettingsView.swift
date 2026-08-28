import SwiftUI

/// API keys live in the login Keychain; Claude/Codex reuse their CLIs' auth.
struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @State private var openRouterKey = Keychain.read(service: OpenRouterProvider.keychainService) ?? ""
    @State private var deepSeekKey = Keychain.read(service: DeepSeekProvider.keychainService) ?? ""
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Auto-detected") {
                detectionRow("Claude (Claude Code login)", detected: ClaudeProvider().isConfigured())
                detectionRow("OpenAI (Codex CLI login)", detected: CodexProvider().isConfigured())
            }
            Section("API keys") {
                SecureField("OpenRouter API key", text: $openRouterKey)
                SecureField("DeepSeek API key", text: $deepSeekKey)
            }
            Button("Save") {
                let savedOpenRouter = Keychain.write(service: OpenRouterProvider.keychainService, value: openRouterKey.trimmed)
                let savedDeepSeek = Keychain.write(service: DeepSeekProvider.keychainService, value: deepSeekKey.trimmed)
                saveError = savedOpenRouter && savedDeepSeek
                    ? nil : "Couldn't save to the Keychain — the previous keys are unchanged."
                store.reloadProviders()
                Task { await store.refreshAll(force: true) }
            }
            if let saveError {
                Text(saveError).foregroundStyle(.red).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private func detectionRow(_ label: String, detected: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: detected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(detected ? .green : .secondary)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

import SwiftUI

struct SettingsView: View {
    @State private var apiKey = ""
    @State private var isRevealed = false
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus: Equatable { case idle, saved, failed }

    var body: some View {
        Form {
            Section("OpenAI API 配置") {
                HStack {
                    Group {
                        if isRevealed {
                            TextField("sk-...", text: $apiKey)
                        } else {
                            SecureField("sk-...", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)

                    Button("保存") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if saveStatus == .saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else if saveStatus == .failed {
                    Label("保存失败，请重试", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Text("API Key 将安全存储在系统 Keychain 中")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("获取 OpenAI API Key →",
                     destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 200)
        .onAppear {
            if let existing = KeychainService.shared.loadAPIKey() {
                apiKey = existing
            }
        }
    }

    private func saveKey() {
        do {
            try KeychainService.shared.save(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
            saveStatus = .saved
            Task {
                try? await Task.sleep(for: .seconds(2))
                saveStatus = .idle
            }
        } catch {
            saveStatus = .failed
        }
    }
}

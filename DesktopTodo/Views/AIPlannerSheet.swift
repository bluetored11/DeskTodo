import SwiftUI

@MainActor
struct AIPlannerSheet: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var planTitle = ""
    @State private var steps: [String] = []
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var hasGenerated = false
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack {
                Label("AI 任务规划", systemImage: "wand.and.stars")
                    .font(.headline)
                Spacer()
                Button {
                    cancelStream()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // ── Scrollable body ───────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Description input row
                    VStack(alignment: .leading, spacing: 6) {
                        Text("描述你想完成的事：")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .top) {
                            TextField("例如：准备下周的项目汇报", text: $description, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...3)
                                .disabled(isStreaming)
                            Button(hasGenerated ? "重新规划" : "开始规划") {
                                startPlanning()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
                        }
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }

                    // No API key warning
                    if KeychainService.shared.loadAPIKey() == nil {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill").foregroundStyle(.orange)
                            Text("请先在设置中填写 OpenAI API Key")
                                .font(.callout)
                            Spacer()
                            SettingsLink { Text("打开设置").font(.callout) }
                        }
                        .padding(10)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Error banner
                    if let msg = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text(msg).font(.callout).foregroundStyle(.red)
                            Spacer()
                            Button("重试") { startPlanning() }.font(.callout)
                        }
                        .padding(10)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Preview card
                    if !planTitle.isEmpty || !steps.isEmpty || isStreaming {
                        VStack(alignment: .leading, spacing: 8) {
                            if !planTitle.isEmpty {
                                Label(planTitle, systemImage: "doc.text")
                                    .font(.headline)
                            }

                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                HStack {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(step)
                                    Spacer()
                                    // Allow delete for all steps except the last one still streaming
                                    if !isStreaming || index < steps.count - 1 {
                                        Button {
                                            steps.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if isStreaming {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.6)
                                    Text("生成中…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────────
            HStack {
                Button("取消") {
                    cancelStream()
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("添加到列表") {
                    addToList()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(steps.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 500)
        .onDisappear { cancelStream() }
    }

    // MARK: - Actions

    private func startPlanning() {
        cancelStream()
        planTitle = ""
        steps = []
        errorMessage = nil
        isStreaming = true
        hasGenerated = true

        streamTask = Task {
            do {
                var lineCount = 0
                for try await line in OpenAIService.shared.streamPlan(description: description) {
                    guard !Task.isCancelled else { break }
                    if lineCount == 0 {
                        planTitle = line
                    } else {
                        steps.append(line)
                    }
                    lineCount += 1
                }
                isStreaming = false
            } catch is CancellationError {
                isStreaming = false
            } catch {
                isStreaming = false
                errorMessage = friendlyError(error)
            }
        }
    }

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func addToList() {
        guard !steps.isEmpty else { return }
        let title = planTitle.isEmpty ? description : planTitle
        store.addItemWithSubTasks(
            title: title.trimmingCharacters(in: .whitespaces),
            subtaskTitles: steps
        )
    }

    private func friendlyError(_ error: Error) -> String {
        if let e = error as? OpenAIError {
            switch e {
            case .noAPIKey:          return "请先在设置中填写 OpenAI API Key"
            case .httpError(401):    return "API Key 无效，请检查设置"
            case .httpError(429):    return "请求过于频繁，请稍后重试"
            case .httpError(let c):  return "API 请求失败（错误码 \(c)）"
            case .invalidResponse:   return "服务器返回异常响应"
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "网络连接失败，请检查网络"
        }
        return "生成失败：\(error.localizedDescription)"
    }
}

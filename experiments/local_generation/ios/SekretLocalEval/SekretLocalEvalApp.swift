import SwiftUI
import UniformTypeIdentifiers

@main
struct SekretLocalEvalApp: App {
    @StateObject private var model = EvaluationViewModel()
    @Environment(\.scenePhase) private var phase
    @State private var importing = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Isolated native evaluation").font(.title2.bold())
                        Text("Fictional prompts only. No account, app model downloads, or shipping Sekret data. Results are not a compatibility or quality approval.")
                            .foregroundStyle(.secondary)
                        Button("Import pinned GGUF from Files") { importing = true }.disabled(model.busy)
                        Text("Choose the verified Qwen3-0.6B Q8_0 file stored locally on this device. Import copies approximately 639 MB into this separate app.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Picker("Context tokens", selection: $model.context) {
                            Text("2,048").tag(2048)
                            Text("4,096").tag(4096)
                        }.pickerStyle(.segmented).disabled(model.busy)
                        Picker("Fictional probe", selection: $model.selectedPrompt) {
                            Text("Concise suggestions").tag(0)
                            Text("Conditional notice").tag(1)
                            Text("Unicode").tag(2)
                            Text("Long output / Stop").tag(3)
                        }.disabled(model.busy)
                        HStack {
                            Button("Run locally") { model.run() }.buttonStyle(.borderedProminent)
                                .disabled(model.busy || !model.hasModel)
                            Button("Stop", role: .destructive) { model.stop() }.buttonStyle(.bordered)
                                .disabled(!model.busy)
                        }
                        Text(model.status).accessibilityAddTraits(.updatesFrequently)
                        if let seconds = model.stopToReturnSeconds {
                            Text("Stop request to worker return: \(seconds, specifier: "%.3f") s. May include suspension/export time; not a GPU-abort guarantee.")
                                .font(.footnote)
                        }
                        if let url = model.exportURL {
                            ShareLink("Export fictional evaluation JSON", item: url)
                        }
                        Text(model.output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Leaving the foreground or receiving a memory warning requests cancellation. Metal work already in flight may finish before cancellation is observed; iOS may suspend or terminate the app first.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding()
                }.navigationTitle("Sekret Local Eval")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result { model.importModel(from: url) }
            }
            .onChange(of: phase) { _, value in model.setForeground(value == .active) }
            .onAppear { model.setForeground(phase == .active) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                model.stop(reason: "Memory warning")
            }
        }
    }
}

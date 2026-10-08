import SwiftUI

@main
struct SekretVisionEvalApp: App {
    @StateObject private var evaluation = VisionEvaluation()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Apple on-device vision screening").font(.title2.bold())
                        Text("Frozen fictional images only. On-device system model; no Private Cloud Compute, no network code, no Sekret data. Not a quality approval.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Run screening suite") { evaluation.run() }
                                .buttonStyle(.borderedProminent).disabled(evaluation.busy)
                            Button("Stop", role: .destructive) { evaluation.stop() }
                                .buttonStyle(.bordered).disabled(!evaluation.busy)
                        }
                        Text(evaluation.status)
                        ForEach(Array(evaluation.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote.monospaced()).textSelection(.enabled)
                        }
                    }.padding()
                }.navigationTitle("Sekret Vision Eval")
            }
            .onAppear {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--screening-suite") { evaluation.run() }
                if arguments.contains("--diagnostic") { evaluation.runDiagnostic() }
            }
        }
    }
}

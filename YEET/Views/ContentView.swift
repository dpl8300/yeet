import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = YEETViewModel()

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .idle:
                Button("Start YEET") {
                    viewModel.start()
                }

            case .waiting:
                Text("Waiting")

            case .airborne:
                Text("Airborne")

            case let .result(result):
                Text("Airtime: \(result.airtime, format: .number.precision(.fractionLength(3))) seconds")
                Button("Start Again") {
                    viewModel.startAgain()
                }

            case .invalid:
                Text("Could not detect a valid YEET")
                Button("Start Again") {
                    viewModel.startAgain()
                }
            }

#if DEBUG
            if let snapshot = viewModel.debugSnapshot {
                Divider()
                DebugPanel(snapshot: snapshot)
            }
#endif
        }
        .padding()
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
        }
    }
}

#if DEBUG
private struct DebugPanel: View {
    let snapshot: DebugSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG")
            Text("State: \(snapshot.state)")
            if let magnitude = snapshot.magnitude {
                Text("Magnitude: \(magnitude, format: .number.precision(.fractionLength(3))) g")
            }
            if let observedSampleRate = snapshot.observedSampleRate {
                Text("Sample rate: \(observedSampleRate, format: .number.precision(.fractionLength(1))) Hz")
            }
            Text("Last: \(snapshot.lastTransition)")
            if let candidateStart = snapshot.candidateStart {
                Text("Start candidate: \(candidateStart, format: .number.precision(.fractionLength(3)))")
            }
            if let candidateEnd = snapshot.candidateEnd {
                Text("End candidate: \(candidateEnd, format: .number.precision(.fractionLength(3)))")
            }
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

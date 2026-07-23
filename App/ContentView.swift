import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Symphonia")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Native host scaffold")
                .foregroundStyle(.secondary)

            TerminalSurfaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}

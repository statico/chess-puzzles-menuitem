import SwiftUI
import AppKit

struct StatsWindowView: View {
    @State private var stats: PuzzleStats = StatsManager.shared.getStats()

    var body: some View {
        VStack(spacing: 20) {
            Text("Puzzle Statistics")
                .font(.system(size: 20, weight: .bold))
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 15) {
                StatRow(title: "Current Streak:", value: "\(stats.currentStreak)")

                StatRow(title: "Total Solved:", value: "\(stats.totalSolved)")

                StatRow(title: "Avg Time (This Week):", value: formatTime(stats.averageSolveTimeThisWeek))

                StatRow(title: "Your Rating:", value: "\(stats.userRating)")
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            refreshStats()
        }
    }

    func refreshStats() {
        stats = StatsManager.shared.getStats()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        if time == 0 {
            return "N/A"
        }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
        }
    }
}

// Wrapper class to maintain compatibility with existing code
public class StatsWindowController: NSWindowController {
    private var hostingController: NSHostingController<StatsWindowView>?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let statsView = StatsWindowView()
        let hostingController = NSHostingController(rootView: statsView)
        self.hostingController = hostingController

        window.contentView = hostingController.view
        window.title = "Statistics"
        window.center()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func updateStats() {
        // Trigger a refresh by accessing the view
        hostingController?.view.setNeedsDisplay(.infinite)
        // The view will refresh on next render cycle
    }
}

#Preview("Statistics Window") {
    StatsWindowView()
        .frame(width: 400, height: 300)
}

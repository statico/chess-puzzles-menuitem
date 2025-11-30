import AppKit

class StatsWindowController: NSWindowController {

    var streakLabel: NSTextField!
    var totalSolvedLabel: NSTextField!
    var averageTimeLabel: NSTextField!
    var ratingLabel: NSTextField!

    private var contentView: NSView?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        setupUI()
        updateStats()
    }

    private func setupUI() {
        guard let window = window else { return }

        window.title = "Statistics"
        window.center()

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        self.contentView = contentView

        let stats = StatsManager.shared.getStats()

        // Title
        let titleLabel = NSTextField(labelWithString: "Puzzle Statistics")
        titleLabel.frame = NSRect(x: 20, y: 240, width: 360, height: 30)
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)

        // Streak
        let streakTitle = NSTextField(labelWithString: "Current Streak:")
        streakTitle.frame = NSRect(x: 40, y: 200, width: 150, height: 20)
        streakTitle.font = NSFont.systemFont(ofSize: 14)
        contentView.addSubview(streakTitle)

        let streakLabel = NSTextField(labelWithString: "\(stats.currentStreak)")
        streakLabel.frame = NSRect(x: 200, y: 200, width: 150, height: 20)
        streakLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        contentView.addSubview(streakLabel)
        self.streakLabel = streakLabel

        // Total Solved
        let totalTitle = NSTextField(labelWithString: "Total Solved:")
        totalTitle.frame = NSRect(x: 40, y: 170, width: 150, height: 20)
        totalTitle.font = NSFont.systemFont(ofSize: 14)
        contentView.addSubview(totalTitle)

        let totalSolvedLabel = NSTextField(labelWithString: "\(stats.totalSolved)")
        totalSolvedLabel.frame = NSRect(x: 200, y: 170, width: 150, height: 20)
        totalSolvedLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        contentView.addSubview(totalSolvedLabel)
        self.totalSolvedLabel = totalSolvedLabel

        // Average Time
        let avgTimeTitle = NSTextField(labelWithString: "Avg Time (This Week):")
        avgTimeTitle.frame = NSRect(x: 40, y: 140, width: 150, height: 20)
        avgTimeTitle.font = NSFont.systemFont(ofSize: 14)
        contentView.addSubview(avgTimeTitle)

        let averageTimeLabel = NSTextField(labelWithString: formatTime(stats.averageSolveTimeThisWeek))
        averageTimeLabel.frame = NSRect(x: 200, y: 140, width: 150, height: 20)
        averageTimeLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        contentView.addSubview(averageTimeLabel)
        self.averageTimeLabel = averageTimeLabel

        // Rating
        let ratingTitle = NSTextField(labelWithString: "Your Rating:")
        ratingTitle.frame = NSRect(x: 40, y: 110, width: 150, height: 20)
        ratingTitle.font = NSFont.systemFont(ofSize: 14)
        contentView.addSubview(ratingTitle)

        let ratingLabel = NSTextField(labelWithString: "\(stats.userRating)")
        ratingLabel.frame = NSRect(x: 200, y: 110, width: 150, height: 20)
        ratingLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        contentView.addSubview(ratingLabel)
        self.ratingLabel = ratingLabel
    }

    func updateStats() {
        let stats = StatsManager.shared.getStats()
        streakLabel.stringValue = "\(stats.currentStreak)"
        totalSolvedLabel.stringValue = "\(stats.totalSolved)"
        averageTimeLabel.stringValue = formatTime(stats.averageSolveTimeThisWeek)
        ratingLabel.stringValue = "\(stats.userRating)"
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


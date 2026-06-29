import Foundation
import Observation

/// A small, self-contained countdown timer for focused writing sessions.
/// Tracks both the remaining time and the total elapsed time (the latter is
/// stored on the entry as `writingSeconds`).
@MainActor
@Observable
final class WritingTimer {
    private(set) var isRunning = false
    private(set) var remainingSeconds: Int
    private(set) var elapsedSeconds = 0
    private(set) var finished = false

    var durationMinutes: Int {
        didSet { if !isRunning { reset() } }
    }

    private var timer: Timer?

    init(durationMinutes: Int = 10) {
        self.durationMinutes = durationMinutes
        self.remainingSeconds = durationMinutes * 60
    }

    /// Reset to a full, stopped countdown for the current duration.
    func reset() {
        stop()
        remainingSeconds = durationMinutes * 60
        elapsedSeconds = 0
        finished = false
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        if remainingSeconds <= 0 { reset() }
        isRunning = true
        finished = false
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor to mutate.
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// Fully stop without resetting elapsed (used on teardown).
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func tick() {
        guard isRunning else { return }
        elapsedSeconds += 1
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        }
        if remainingSeconds == 0 {
            finished = true
            pause()
        }
    }

    /// "MM:SS" of the remaining time.
    var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 0…1 progress through the configured duration.
    var progress: Double {
        let total = max(1, durationMinutes * 60)
        return Double(total - remainingSeconds) / Double(total)
    }
}

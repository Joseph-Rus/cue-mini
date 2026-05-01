import Foundation
import SwiftUI
import Combine

enum Phase: Equatable {
    case idle
    case listening
    case matched(MatchResult)
    case noMatch
    case error(String)
}

struct MatchResult: Equatable {
    let title: String
    let artist: String
    let confidence: Int
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: Phase = .idle
    @Published var audioLevel: Float = 0
    @Published var settingsOpen: Bool = false

    private let recognizer = ShazamRecognizer()
    private var listenTimeoutTask: Task<Void, Never>?
    private var autoDismissTask: Task<Void, Never>?
    private var levelObservation: AnyCancellable?

    // Hard cap on how long we listen before declaring "no match"
    private let listenTimeoutSeconds: TimeInterval = 12

    private init() {
        recognizer.onMatch = { [weak self] result in
            Task { @MainActor in self?.handleMatch(result) }
        }
        recognizer.onNoMatch = { [weak self] in
            Task { @MainActor in self?.handleNoMatch() }
        }
        recognizer.onError = { [weak self] message in
            Task { @MainActor in self?.handleError(message) }
        }
        recognizer.onLevel = { [weak self] level in
            Task { @MainActor in self?.audioLevel = level }
        }
    }

    func toggleListening() {
        switch phase {
        case .idle, .matched, .noMatch, .error:
            startListening()
        case .listening:
            stop()
        }
    }

    func startListening() {
        cancelTimers()
        audioLevel = 0
        phase = .listening

        let capturer: AudioCapturer
        switch Settings.shared.audioSource {
        case .systemAudio:
            if #available(macOS 13.0, *) {
                capturer = SystemAudioCapturer()
            } else {
                handleError("System audio capture requires macOS 13 or later.")
                return
            }
        case .microphone:
            capturer = MicrophoneCapturer(deviceUID: Settings.shared.audioDeviceUID)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.recognizer.start(using: capturer)
                await MainActor.run { self.startListenTimeout() }
            } catch {
                await MainActor.run { self.handleError(error.localizedDescription) }
            }
        }
    }

    private func startListenTimeout() {
        listenTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.listenTimeoutSeconds ?? 12) * 1_000_000_000))
            guard let self else { return }
            if case .listening = self.phase {
                self.recognizer.stop()
                self.handleNoMatch()
            }
        }
    }

    func stop() {
        cancelTimers()
        recognizer.stop()
        audioLevel = 0
        phase = .idle
    }

    func goBack() {
        cancelTimers()
        recognizer.stop()
        audioLevel = 0
        phase = .idle
    }

    private func handleMatch(_ result: MatchResult) {
        cancelTimers()
        recognizer.stop()
        phase = .matched(result)
        scheduleAutoDismissIfEnabled()
    }

    private func handleNoMatch() {
        cancelTimers()
        recognizer.stop()
        audioLevel = 0
        phase = .noMatch
        scheduleAutoDismissIfEnabled()
    }

    private func handleError(_ message: String) {
        cancelTimers()
        recognizer.stop()
        audioLevel = 0
        phase = .error(message)
    }

    private func scheduleAutoDismissIfEnabled() {
        guard Settings.shared.autoDismissEnabled else { return }
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            if Task.isCancelled { return }
            switch self.phase {
            case .matched, .noMatch:
                self.phase = .idle
            default:
                break
            }
        }
    }

    private func cancelTimers() {
        listenTimeoutTask?.cancel()
        listenTimeoutTask = nil
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }
}

import Foundation
import ShazamKit
import AVFoundation

/// Bridges an `AudioCapturer` (mic or system audio) to a Shazam session and
/// surfaces match / no-match / error / level events to the app.
final class ShazamRecognizer: NSObject, SHSessionDelegate, @unchecked Sendable {
    var onMatch: ((MatchResult) -> Void)?
    var onNoMatch: (() -> Void)?
    var onError: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    private var session: SHSession?
    private var capturer: AudioCapturer?

    func start(using capturer: AudioCapturer) async throws {
        stop()

        // Use the user's custom catalog if any songs are loaded — ShazamKit
        // matches it alongside (not instead of) the public catalog when the
        // SHSession is created with a catalog argument. The catalog isn't
        // formally Sendable, so we build the session on the main actor.
        let session: SHSession = await MainActor.run {
            if let catalog = CatalogStore.shared.customCatalog {
                return SHSession(catalog: catalog)
            } else {
                return SHSession()
            }
        }
        session.delegate = self
        self.session = session

        capturer.onBuffer = { [weak self] buffer, time in
            self?.session?.matchStreamingBuffer(buffer, at: time)
        }
        capturer.onLevel = { [weak self] level in
            self?.onLevel?(level)
        }
        capturer.onError = { [weak self] message in
            self?.onError?(message)
        }
        self.capturer = capturer

        try await capturer.start()
    }

    func stop() {
        capturer?.stop()
        capturer?.onBuffer = nil
        capturer?.onLevel = nil
        capturer?.onError = nil
        capturer = nil
        session = nil
    }

    // MARK: - SHSessionDelegate

    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let title = item.title ?? "Unknown title"
        let artist = item.artist ?? ""
        let confidence = min(99, 90 + min(9, match.mediaItems.count - 1))
        let result = MatchResult(title: title, artist: artist, confidence: confidence)
        onMatch?(result)
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        if let error {
            onError?(error.localizedDescription)
        }
        // No-match for the listen window is reported by AppState's timeout.
    }
}

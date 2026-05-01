import Foundation
import AVFoundation
import ShazamKit
import Combine

/// One song the user has added to their custom catalog.
struct LibrarySong: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    /// Persisted relative path inside the library directory. The actual fingerprint
    /// is regenerated from the source audio whenever the catalog is rebuilt — we
    /// could cache the SHSignature but keeping the source file is more robust.
    var sourceFilename: String

    init(id: UUID = UUID(), title: String, artist: String, sourceFilename: String) {
        self.id = id
        self.title = title
        self.artist = artist
        self.sourceFilename = sourceFilename
    }
}

/// Persistent store for the user's custom catalog. Owns:
///   - A folder on disk holding the source audio files + metadata index
///   - The in-memory `[LibrarySong]` array (published for SwiftUI)
///   - The fingerprinted `SHCustomCatalog` used at recognition time
@MainActor
final class CatalogStore: ObservableObject {
    static let shared = CatalogStore()

    @Published private(set) var songs: [LibrarySong] = []
    @Published private(set) var isBuilding: Bool = false
    @Published private(set) var lastError: String? = nil

    /// The compiled custom catalog. nil until at least one song is fingerprinted
    /// successfully and rebuild has completed.
    private(set) var customCatalog: SHCustomCatalog? = nil

    private let libraryDir: URL
    private let audioDir: URL
    private let indexURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.libraryDir = appSupport.appendingPathComponent("Cue Mini", isDirectory: true)
        self.audioDir = libraryDir.appendingPathComponent("audio", isDirectory: true)
        self.indexURL = libraryDir.appendingPathComponent("library.json")

        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        loadIndex()
        Task { await rebuildCatalog() }
    }

    // MARK: - Mutation

    func addSongs(_ candidates: [AddCandidate]) async {
        for c in candidates {
            do {
                let copied = try copyIntoLibrary(source: c.url)
                let song = LibrarySong(
                    title: c.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? c.url.deletingPathExtension().lastPathComponent
                        : c.title,
                    artist: c.artist,
                    sourceFilename: copied.lastPathComponent
                )
                songs.append(song)
            } catch {
                lastError = "Could not add \(c.url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        saveIndex()
        await rebuildCatalog()
    }

    func removeSong(_ song: LibrarySong) async {
        let fileURL = audioDir.appendingPathComponent(song.sourceFilename)
        try? FileManager.default.removeItem(at: fileURL)
        songs.removeAll { $0.id == song.id }
        saveIndex()
        await rebuildCatalog()
    }

    func updateSong(_ updated: LibrarySong) {
        guard let i = songs.firstIndex(where: { $0.id == updated.id }) else { return }
        songs[i] = updated
        saveIndex()
        // Metadata-only edits don't require re-fingerprinting, but the catalog
        // holds the title/artist as MediaItem so we still rebuild.
        Task { await rebuildCatalog() }
    }

    // MARK: - Fingerprint / catalog build

    func rebuildCatalog() async {
        guard !songs.isEmpty else {
            customCatalog = nil
            return
        }

        isBuilding = true
        defer { isBuilding = false }

        let catalog = SHCustomCatalog()
        for song in songs {
            let url = audioDir.appendingPathComponent(song.sourceFilename)
            do {
                let signature = try await fingerprint(url: url)
                let item = SHMediaItem(properties: [
                    .title: song.title,
                    .artist: song.artist,
                    .shazamID: song.id.uuidString
                ])
                try catalog.addReferenceSignature(signature, representing: [item])
            } catch {
                lastError = "Could not fingerprint \(song.title): \(error.localizedDescription)"
            }
        }
        customCatalog = catalog
    }

    /// Generate a Shazam signature from an audio file by streaming its samples
    /// through SHSignatureGenerator.
    private func fingerprint(url: URL) async throws -> SHSignature {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let generator = SHSignatureGenerator()

        let chunkFrames: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NSError(domain: "CueMini", code: -100, userInfo: [
                NSLocalizedDescriptionKey: "Could not allocate read buffer for \(url.lastPathComponent)."
            ])
        }

        while true {
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try generator.append(buffer, at: nil)
            if buffer.frameLength < chunkFrames { break }
        }
        return generator.signature()
    }

    // MARK: - Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([LibrarySong].self, from: data)
        else {
            songs = []
            return
        }
        songs = decoded
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(songs)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            lastError = "Could not save library index: \(error.localizedDescription)"
        }
    }

    private func copyIntoLibrary(source: URL) throws -> URL {
        let needsScopedAccess = source.startAccessingSecurityScopedResource()
        defer { if needsScopedAccess { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension
        let unique = "\(UUID().uuidString).\(ext)"
        let dest = audioDir.appendingPathComponent(unique)
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }
}

// MARK: - Add candidate

struct AddCandidate {
    let url: URL
    var title: String
    var artist: String
}

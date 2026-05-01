import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject private var store = CatalogStore.shared
    @ObservedObject private var theme = ThemeObserver.shared
    @State private var editing: LibrarySong? = nil
    @State private var hovering = false

    private var songListHeight: CGFloat {
        // ~50 px per song row + ~360 px of header/actions/dropzone/footer chrome.
        let chrome: CGFloat = 360
        let perRow: CGFloat = 50
        let rows = max(0, store.songs.count)
        return min(720, chrome + CGFloat(rows) * perRow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            actions
            dropZone
            songList
            footer
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 360, idealHeight: songListHeight, maxHeight: 720)
        .background(theme.palette.cardBg.ignoresSafeArea())
        .sheet(item: $editing) { song in
            EditSongSheet(song: song) { updated in
                store.updateSong(updated)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("↳")
                Text("LIBRARY")
                    .tracking(1.4)
            }
            .font(Typeface.mono(11, weight: .medium))
            .foregroundStyle(theme.palette.fgTertiary)

            Text("Custom Catalog")
                .font(Typeface.display(26, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(theme.palette.fgPrimary)

            Text("Add songs that aren't in Shazam's public catalog. Cue Mini will recognize them in addition to the regular Shazam catalog.")
                .font(Typeface.body(12, italic: true))
                .foregroundStyle(theme.palette.fgSecondary)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            PrimaryButton(label: "Add Songs…", systemImage: "plus") {
                pickFiles(allowsDirectories: false)
            }
            PrimaryButton(label: "Import Folder…", systemImage: "folder") {
                pickFiles(allowsDirectories: true)
            }
            Spacer()
            if store.isBuilding {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Fingerprinting…")
                        .font(Typeface.body(11, italic: true))
                        .foregroundStyle(theme.palette.fgSecondary)
                }
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .foregroundStyle(hovering ? theme.palette.fgPrimary : theme.palette.cardBorder)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hovering ? theme.palette.controlBg : .clear)
                )

            VStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.palette.fgTertiary)
                Text("Drop audio files or a folder here")
                    .font(Typeface.body(12, weight: .medium))
                    .foregroundStyle(theme.palette.fgSecondary)
            }
        }
        .frame(height: 78)
        .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    @ViewBuilder
    private var songList: some View {
        if store.songs.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("↳")
                    Text("\(store.songs.count) SONG\(store.songs.count == 1 ? "" : "S")")
                        .tracking(1.4)
                }
                .font(Typeface.mono(10, weight: .medium))
                .foregroundStyle(theme.palette.fgTertiary)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.songs) { song in
                            SongRow(
                                song: song,
                                onEdit: { editing = song },
                                onRemove: { Task { await store.removeSong(song) } }
                            )
                            if song != store.songs.last {
                                Divider().background(theme.palette.cardBorder)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let err = store.lastError {
                Text(err)
                    .font(Typeface.body(11, italic: true))
                    .foregroundStyle(theme.palette.accentError)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    // MARK: - File picker / drop

    private func pickFiles(allowsDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !allowsDirectories
        panel.canChooseDirectories = allowsDirectories
        panel.allowsMultipleSelection = !allowsDirectories
        if !allowsDirectories {
            panel.allowedContentTypes = audioContentTypes
        }
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            await ingest(urls: urls)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for p in providers {
                if let url = await loadURL(from: p) {
                    urls.append(url)
                }
            }
            await ingest(urls: urls)
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private func ingest(urls: [URL]) async {
        let files = urls.flatMap(expandToAudioFiles)
        var candidates: [AddCandidate] = []
        for url in files {
            let (title, artist) = await readTitleArtist(from: url)
            candidates.append(AddCandidate(
                url: url,
                title: title ?? url.deletingPathExtension().lastPathComponent,
                artist: artist ?? ""
            ))
        }
        await store.addSongs(candidates)
    }

    /// Best-effort ID3/M4A metadata read. Returns (title, artist) or nils.
    private func readTitleArtist(from url: URL) async -> (String?, String?) {
        let asset = AVURLAsset(url: url)
        do {
            let items = try await asset.load(.commonMetadata)
            var title: String? = nil
            var artist: String? = nil
            for item in items {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle, title == nil {
                    title = try? await item.load(.stringValue)
                }
                if key == .commonKeyArtist, artist == nil {
                    artist = try? await item.load(.stringValue)
                }
            }
            return (title, artist)
        } catch {
            return (nil, nil)
        }
    }

    private func expandToAudioFiles(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return isAudioFile(url) ? [url] : [] }
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
        var found: [URL] = []
        while let next = walker?.nextObject() as? URL {
            if isAudioFile(next) { found.append(next) }
        }
        return found
    }

    private func isAudioFile(_ url: URL) -> Bool {
        let exts = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"]
        return exts.contains(url.pathExtension.lowercased())
    }

    private var audioContentTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .wav, .aiff]
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        return types
    }
}

// MARK: - Song row

private struct SongRow: View {
    let song: LibrarySong
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(Typeface.body(13, weight: .medium))
                    .foregroundStyle(theme.palette.fgPrimary)
                    .lineLimit(1)
                Text(song.artist.isEmpty ? "Unknown artist" : song.artist)
                    .font(Typeface.body(11, italic: true))
                    .foregroundStyle(theme.palette.fgSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if hovering {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.palette.fgSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit")

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.palette.fgSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from library")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Edit sheet

private struct EditSongSheet: View {
    let song: LibrarySong
    let onSave: (LibrarySong) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @ObservedObject private var theme = ThemeObserver.shared

    init(song: LibrarySong, onSave: @escaping (LibrarySong) -> Void) {
        self.song = song
        self.onSave = onSave
        _title = State(initialValue: song.title)
        _artist = State(initialValue: song.artist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Song")
                .font(Typeface.display(18, weight: .bold))
                .foregroundStyle(theme.palette.fgPrimary)

            field(label: "TITLE", text: $title)
            field(label: "ARTIST", text: $artist)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var updated = song
                    updated.title = title
                    updated.artist = artist
                    onSave(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(theme.palette.cardBg.ignoresSafeArea())
    }

    private func field(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typeface.mono(10, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(theme.palette.fgTertiary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Primary button

private struct PrimaryButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(Typeface.body(12, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? theme.palette.controlBgHover : theme.palette.controlBg)
            )
            .foregroundStyle(theme.palette.fgPrimary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

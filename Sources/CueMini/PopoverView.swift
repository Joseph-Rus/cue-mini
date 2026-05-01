import SwiftUI
import AppKit

// Editorial card — the unifying visual treatment for every popover state.
struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: Settings
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        ZStack {
            theme.palette.cardBg
            stateContent
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 16)
        }
        .frame(width: 420)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.palette.cardBorder, lineWidth: 0.5)
        )
        .padding(8)
        .background(Color.clear)
        .onExitCommand { handleEscape() }
        .onChange(of: settings.appearance) { theme.refresh() }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state.phase {
        case .idle:        IdleCard()
        case .listening:   ListeningCard()
        case .matched(let r): MatchCard(result: r)
        case .noMatch:     NoMatchCard()
        case .error(let m): ErrorCard(message: m)
        }
    }

    private func handleEscape() {
        switch state.phase {
        case .matched, .noMatch, .error:
            state.goBack()
        case .listening:
            state.stop()
        case .idle:
            NSApp.keyWindow?.orderOut(nil)
        }
    }
}

// MARK: - State caption ("↳ IDENTIFIED" etc.)

private struct StateCaption: View {
    let label: String
    var color: Color? = nil
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        HStack(spacing: 6) {
            Text("↳")
                .font(Typeface.mono(11, weight: .medium))
                .foregroundStyle(color ?? theme.palette.fgTertiary)
            Text(label)
                .font(Typeface.mono(11, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(color ?? theme.palette.fgTertiary)
        }
    }
}

// MARK: - Idle

private struct IdleCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                StateCaption(label: "READY")
                Spacer()
                HStack(spacing: 4) {
                    Text("⌥")
                    Text("Space")
                }
                .font(Typeface.mono(11, weight: .medium))
                .foregroundStyle(theme.palette.fgTertiary)
            }
            .padding(.bottom, 14)

            HStack(alignment: .center) {
                ListenButton { state.startListening() }

                Text("Tap to identify what's playing")
                    .font(Typeface.body(13, italic: true))
                    .foregroundStyle(theme.palette.fgSecondary)
                    .padding(.leading, 16)

                Spacer()
            }
            .padding(.vertical, 8)

            Spacer(minLength: 14)

            HStack {
                Spacer()
                IconButton(systemName: "music.note.list", help: "Library") {
                    LibraryWindowController.shared.show()
                }
                IconButton(systemName: "gearshape", help: "Settings") {
                    SettingsWindowController.shared.show()
                }
            }
        }
    }
}

// MARK: - Listening

private struct ListeningCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var theme = ThemeObserver.shared
    @State private var bars: [CGFloat] = Array(repeating: 4, count: 26)
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                StateCaption(label: "LISTENING")
                Spacer()
                Circle()
                    .fill(theme.palette.accentListening)
                    .frame(width: 6, height: 6)
                    .opacity(0.9)
                    .scaleEffect(state.audioLevel > 0.05 ? 1.4 : 0.8)
                    .animation(.easeInOut(duration: 0.4), value: state.audioLevel)
            }
            .padding(.bottom, 18)

            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.palette.fgSecondary)
                        .frame(width: 3, height: max(4, h))
                }
            }
            .frame(height: 36)

            Text("Listening for ~10 seconds…")
                .font(Typeface.body(13, italic: true))
                .foregroundStyle(theme.palette.fgSecondary)
                .padding(.top, 12)

            Spacer(minLength: 12)

            HStack {
                Spacer()
                IconButton(systemName: "xmark", help: "Cancel") {
                    state.stop()
                }
            }
        }
        .onAppear { startMeter() }
        .onDisappear { stopMeter() }
    }

    private func startMeter() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            Task { @MainActor in
                let level = AppState.shared.audioLevel
                let target = 4 + CGFloat(level) * 32
                var next = bars
                next.removeFirst()
                next.append(target * CGFloat.random(in: 0.65...1.0))
                bars = next
            }
        }
    }

    private func stopMeter() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Match (the "Midnight Drift" mock)

private struct MatchCard: View {
    let result: MatchResult
    @EnvironmentObject var state: AppState
    @ObservedObject private var theme = ThemeObserver.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                StateCaption(label: "IDENTIFIED")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 6, height: 6)
                    Text("\(result.confidence)")
                        .font(Typeface.mono(12, weight: .semibold))
                        .foregroundStyle(confidenceColor)
                }
            }
            .padding(.bottom, 12)

            Text(result.title)
                .font(Typeface.display(30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(theme.palette.fgPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(alignment: .center) {
                Text(result.artist.isEmpty ? "Unknown artist" : result.artist)
                    .font(Typeface.body(13, italic: true))
                    .foregroundStyle(theme.palette.fgSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                HStack(spacing: 14) {
                    IconButton(
                        systemName: copied ? "checkmark" : "doc.on.doc",
                        help: copied ? "Copied" : "Copy title",
                        tint: copied ? theme.palette.accentMatched : nil
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.title, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            copied = false
                        }
                    }
                    IconButton(systemName: "arrow.clockwise", help: "Listen again") {
                        state.startListening()
                    }
                    IconButton(systemName: "xmark", help: "Dismiss") {
                        state.goBack()
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private var confidenceColor: Color {
        result.confidence >= 80 ? theme.palette.accentMatched : theme.palette.accentMedium
    }
}

// MARK: - No match

private struct NoMatchCard: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StateCaption(label: "NOT IDENTIFIED")
                .padding(.bottom, 12)

            Text("No match.")
                .font(Typeface.display(30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(theme.palette.fgPrimary)

            HStack(alignment: .center) {
                Text("Try again with clearer audio")
                    .font(Typeface.body(13, italic: true))
                    .foregroundStyle(theme.palette.fgSecondary)

                Spacer()

                HStack(spacing: 14) {
                    IconButton(systemName: "arrow.clockwise", help: "Listen again") {
                        state.startListening()
                    }
                    IconButton(systemName: "xmark", help: "Dismiss") {
                        state.goBack()
                    }
                }
            }
            .padding(.top, 10)
        }
    }
}

// MARK: - Error

private struct ErrorCard: View {
    let message: String
    @EnvironmentObject var state: AppState
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StateCaption(label: "ERROR", color: theme.palette.accentError)
                .padding(.bottom, 12)

            Text("Something went wrong.")
                .font(Typeface.display(26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(theme.palette.fgPrimary)

            Text(message)
                .font(Typeface.body(12))
                .foregroundStyle(theme.palette.accentError)
                .lineLimit(3)
                .padding(.top, 6)

            HStack {
                Spacer()
                IconButton(systemName: "xmark", help: "Dismiss") {
                    state.goBack()
                }
            }
            .padding(.top, 12)
        }
    }
}

// MARK: - ListenButton (circular primary action)

private struct ListenButton: View {
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.palette.fgPrimary)
                    .frame(width: 64, height: 64)
                    .scaleEffect(pressed ? 0.94 : (hovering ? 1.04 : 1.0))
                    .shadow(
                        color: theme.palette.fgPrimary.opacity(hovering ? 0.18 : 0),
                        radius: hovering ? 12 : 0,
                        y: 2
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.palette.cardBg)
                    .scaleEffect(pressed ? 0.94 : (hovering ? 1.04 : 1.0))
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.easeOut(duration: 0.10), value: pressed)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .help("Identify what's playing (⌥Space)")
    }
}

// MARK: - IconButton (minimal, label-less)

struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var hovering = false
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint ?? (hovering ? theme.palette.controlIconHover : theme.palette.controlIconIdle))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

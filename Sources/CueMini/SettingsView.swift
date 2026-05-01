import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @ObservedObject private var theme = ThemeObserver.shared
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            VStack(alignment: .leading, spacing: 24) {
                section(label: "SOURCE") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(AudioSource.allCases) { src in
                                SourceRow(
                                    source: src,
                                    selected: settings.audioSource == src
                                ) {
                                    settings.audioSource = src
                                }
                            }
                        }

                        if settings.audioSource == .microphone {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Device")
                                    .font(Typeface.body(13, weight: .medium))
                                    .foregroundStyle(theme.palette.fgPrimary)
                                Picker("", selection: bind(\.audioDeviceUID)) {
                                    Text("System default").tag("")
                                    ForEach(devices) { d in
                                        Text(d.name).tag(d.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .controlSize(.regular)
                            }
                            .padding(.top, 4)
                        }

                        if settings.audioSource == .systemAudio {
                            Text("First use will request Screen Recording permission. Cue Mini does not record your screen — macOS groups system-audio capture under that permission.")
                                .font(Typeface.body(11, italic: true))
                                .foregroundStyle(theme.palette.fgTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }

                divider

                section(label: "APPEARANCE") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Theme")
                            .font(Typeface.body(13, weight: .medium))
                            .foregroundStyle(theme.palette.fgPrimary)
                        HStack(spacing: 8) {
                            ForEach(AppearanceMode.allCases) { mode in
                                AppearanceChip(
                                    mode: mode,
                                    selected: settings.appearance == mode
                                ) {
                                    settings.appearance = mode
                                    theme.refresh()
                                }
                            }
                        }
                    }
                }

                divider

                section(label: "BEHAVIOR") {
                    Toggle(isOn: bind(\.autoDismissEnabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-dismiss after match")
                                .font(Typeface.body(13, weight: .medium))
                                .foregroundStyle(theme.palette.fgPrimary)
                            Text("Returns to idle 5 seconds after a match is found")
                                .font(Typeface.body(11, italic: true))
                                .foregroundStyle(theme.palette.fgSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(28)
        .frame(width: 460, height: 480)
        .background(theme.palette.cardBg.ignoresSafeArea())
        .onAppear {
            devices = AudioDevices.listInputs()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("↳")
                    .font(Typeface.mono(11, weight: .medium))
                Text("SETTINGS")
                    .font(Typeface.mono(11, weight: .medium))
                    .tracking(1.4)
            }
            .foregroundStyle(theme.palette.fgTertiary)

            Text("Cue Mini")
                .font(Typeface.display(26, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(theme.palette.fgPrimary)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.palette.cardBorder)
            .frame(height: 0.5)
    }

    private var footer: some View {
        HStack {
            Button(action: { NSApp.terminate(nil) }) {
                Text("Quit Cue Mini")
                    .font(Typeface.body(12, italic: true))
                    .foregroundStyle(theme.palette.fgSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("v0.1.0")
                .font(Typeface.mono(11))
                .foregroundStyle(theme.palette.fgQuaternary)
        }
    }

    @ViewBuilder
    private func section<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("↳")
                Text(label)
                    .tracking(1.4)
            }
            .font(Typeface.mono(10, weight: .medium))
            .foregroundStyle(theme.palette.fgTertiary)

            content()
        }
    }

    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Source row (radio-style)

private struct SourceRow: View {
    let source: AudioSource
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            selected ? theme.palette.fgPrimary : theme.palette.fgQuaternary,
                            lineWidth: selected ? 5 : 1
                        )
                        .frame(width: 14, height: 14)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.label)
                        .font(Typeface.body(13, weight: .medium))
                        .foregroundStyle(theme.palette.fgPrimary)
                    Text(source.helperText)
                        .font(Typeface.body(11, italic: true))
                        .foregroundStyle(theme.palette.fgSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? theme.palette.controlBg : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? theme.palette.fgQuaternary : theme.palette.cardBorder,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Appearance chip

private struct AppearanceChip: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false
    @ObservedObject private var theme = ThemeObserver.shared

    var body: some View {
        Button(action: action) {
            Text(mode.label)
                .font(Typeface.body(12, weight: .medium))
                .foregroundStyle(selected ? theme.palette.fgPrimary : theme.palette.fgSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? theme.palette.controlBgHover : (hovering ? theme.palette.controlBg : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? theme.palette.fgQuaternary : theme.palette.cardBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

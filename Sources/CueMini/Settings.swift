import Foundation
import SwiftUI
import Combine

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AudioSource: String, CaseIterable, Identifiable {
    case systemAudio
    case microphone

    var id: String { rawValue }
    var label: String {
        switch self {
        case .systemAudio: return "System Audio"
        case .microphone: return "Microphone"
        }
    }
    var helperText: String {
        switch self {
        case .systemAudio: return "Captures whatever your Mac is playing"
        case .microphone: return "Captures sound through a physical microphone"
        }
    }
}

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @AppStorage("audioDeviceUID") var audioDeviceUID: String = ""
    @AppStorage("autoDismissEnabled") var autoDismissEnabled: Bool = true
    @AppStorage("appearanceRaw") private var appearanceRaw: String = AppearanceMode.system.rawValue
    @AppStorage("audioSourceRaw") private var audioSourceRaw: String = AudioSource.systemAudio.rawValue

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set {
            appearanceRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var audioSource: AudioSource {
        get { AudioSource(rawValue: audioSourceRaw) ?? .systemAudio }
        set {
            audioSourceRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    private init() {}
}

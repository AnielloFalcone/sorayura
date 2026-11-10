import AudioToolbox
import CoreAudio
import SwiftUI

enum OutputVolume {
    static func outputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout.size(ofValue: id))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func control(on device: AudioDeviceID) -> (AudioObjectPropertyAddress, Float32)? {
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                    mElement: kAudioObjectPropertyElementMain)
            var writable = DarwinBoolean(false)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout.size(ofValue: value))
            if AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue,
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, value.isFinite {
                return (address, value)
            }
        }
        return nil
    }

    static func read() -> Int? {
        guard let device = outputDevice(), let (_, value) = control(on: device) else { return nil }
        return Int((min(1, max(0, value)) * 100).rounded())
    }

    static func write(_ percent: Int) -> Bool {
        guard let device = outputDevice(), let (property, _) = control(on: device) else { return false }
        var address = property
        var value = Float32(min(100, max(0, percent))) / 100
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value) == noErr
    }
}

struct AudioMixerView: View {
    let model: Model
    @State private var output: Int?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let output {
                VolumeSlider(name: L("Volume generale"), volume: output) { value in
                    error = OutputVolume.write(value) ? nil : "Impossibile cambiare il volume generale."
                    self.output = OutputVolume.read()
                }
            } else {
                Text(L("L’uscita audio attiva non espone un controllo del volume."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.prefs.spotifyEnabled == true, model.spotifySupports("volumeUp") {
                if model.prefs.spotifySource == "web" {
                    HStack {
                        Text("Spotify Web")
                        Spacer()
                        Button { model.spotifyCommand("volumeDown") } label: { Image(systemName: "speaker.minus") }
                            .accessibilityLabel(L("Abbassa volume"))
                        Text("\(model.spotify.volume)%").monospacedDigit()
                        Button { model.spotifyCommand("volumeUp") } label: { Image(systemName: "speaker.plus") }
                            .accessibilityLabel(L("Alza volume"))
                    }
                } else {
                    VolumeSlider(name: "Spotify", volume: model.spotify.volume) { value in
                        change { try await model.setSpotifyVolume(value) }
                    }
                }
            }
            if model.prefs.appleMusicEnabled == true, model.appleMusicSupports("volumeUp") {
                VolumeSlider(name: "Apple Music", volume: model.appleMusic.volume) { value in
                    change { try await model.setAppleMusicVolume(value) }
                }
            }
            Text(L("I controlli per app compaiono quando Spotify o Apple Music sono collegati e il volume è disponibile."))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if #available(macOS 15, *) {
                Text(L("App nel widget")).font(.headline)
                HStack {
                    Button(L("Richiedi accesso all’audio…")) {
                        Task { await model.processMixer.requestPermission() }
                    }.disabled(model.processMixer.requestingPermission)
                    Button(L("Apri impostazioni privacy…")) { ProcessMixer.openAudioPrivacySettings() }
                }
                Text(L("Avvia l’audio nell’app che vuoi controllare, poi selezionala qui. Ridurre il volume richiede l’accesso all’audio di sistema."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.processMixer.available) { process in
                    Toggle(isOn: Binding(
                        get: { model.processMixer.selected.contains(process) },
                        set: { model.processMixer.select(process, $0) })) {
                        HStack {
                            if let icon = NSRunningApplication(processIdentifier: process.pid)?.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            }
                            Text(process.name)
                        }
                    }
                    if model.processMixer.selected.contains(process) {
                        VolumeSlider(name: process.name, volume: model.processMixer.levels[process.id] ?? 100) {
                            model.processMixer.set(process, volume: $0)
                        }
                    }
                }
                if model.processMixer.error {
                    Text(L("Controllo del processo non disponibile. Verifica il permesso di cattura audio e l’uscita attiva."))
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text(L("Il volume per processo richiede macOS 15 o successivo.")).font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(L(error)).font(.caption).foregroundStyle(.orange) }
        }
        .task {
            while !Task.isCancelled {
                output = OutputVolume.read()
                model.processMixer.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func change(_ action: @escaping @MainActor () async throws -> Void) {
        error = nil
        Task {
            do { try await action() }
            catch { self.error = "L’app non ha accettato il cambio di volume." }
        }
    }
}

struct VolumeSlider: View {
    let name: String
    let volume: Int
    let commit: (Int) -> Void
    @State private var draft: Double?
    @State private var editing = false

    var body: some View {
        HStack {
            Text(name).frame(minWidth: 105, alignment: .leading)
            Slider(value: Binding(get: { draft ?? Double(volume) }, set: {
                if editing { draft = $0 } else { commit(Int($0)) }
            }), in: 0...100, step: 1) {
                Text(name)
            } onEditingChanged: { editing in
                self.editing = editing
                if !editing, let draft {
                    self.draft = nil
                    commit(Int(draft))
                }
            }.labelsHidden().accessibilityLabel(name)
            Text("\(Int(draft ?? Double(volume)))%").monospacedDigit().frame(minWidth: 42, alignment: .trailing)
        }
    }
}

struct MixerWidget: View {
    let mixer: ProcessMixer
    static let headerHeight: CGFloat = 28
    static let rowHeight: CGFloat = 42
    static let footerHeight: CGFloat = 28

    static func preferredHeight(count: Int) -> CGFloat {
        32 + headerHeight + CGFloat(1 + min(count, 5)) * rowHeight + (count == 0 || count > 5 ? footerHeight : 0)
    }

    private struct Layout {
        let page: Int
        let pages: Int
        let rows: [AudioProcess]

        init(height: CGFloat, selected: [AudioProcess], requestedPage: Int) {
            let space = max(0, height - headerHeight - rowHeight)
            let needsPages = CGFloat(selected.count) * rowHeight > space
            let capacity = max(1, Int((space - (needsPages ? footerHeight : 0)) / rowHeight))
            pages = max(1, (selected.count + capacity - 1) / capacity)
            page = min(requestedPage, pages - 1)
            rows = Array(selected.dropFirst(page * capacity).prefix(capacity))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(height: geometry.size.height, selected: mixer.selected, requestedPage: mixer.page)
            VStack(spacing: 0) {
                HStack {
                    Label(L("Mixer audio"), systemImage: "slider.horizontal.3")
                    Spacer()
                    if mixer.error { Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow) }
                    Image(systemName: "checklist").frame(width: 28, height: 24)
                        .background(.white.opacity(0.12), in: .rect(cornerRadius: 6))
                }.font(.system(size: 12, weight: .semibold)).frame(height: Self.headerHeight)
                row(L("Volume generale"), icon: nil, volume: mixer.outputVolume)
                ForEach(layout.rows) { process in
                    row(process.name, icon: NSRunningApplication(processIdentifier: process.pid)?.icon,
                        volume: mixer.levels[process.id] ?? 100)
                }
                if layout.rows.isEmpty {
                    Label(L("Scegli app…"), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: Self.footerHeight).font(.caption)
                } else if layout.pages > 1 {
                    HStack {
                        Image(systemName: "chevron.left")
                        Spacer()
                        Text("\(layout.page + 1) / \(layout.pages)")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.padding(.horizontal, 12).frame(height: Self.footerHeight).font(.caption)
                }
            }
        }.task {
            while !Task.isCancelled {
                mixer.refreshOutput()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func row(_ name: String, icon: NSImage?, volume: Int?) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon { Image(nsImage: icon).resizable().scaledToFit() }
                else { Image(systemName: "speaker.wave.2") }
            }.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).lineLimit(1)
                GeometryReader { track in
                    let level = CGFloat(volume ?? 0) / 100
                    Capsule().fill(.white.opacity(0.17)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.blue).frame(width: track.size.width * level)
                        }
                        .overlay(alignment: .leading) {
                            Circle().fill(.white).frame(width: 10, height: 10)
                                .offset(x: max(0, track.size.width - 10) * level)
                        }
                }.frame(height: 4)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(volume.map { "\($0)%" } ?? "—").monospacedDigit().frame(width: 38)
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 24, height: 24)
        }.font(.system(size: 11)).frame(height: Self.rowHeight)
            .opacity(volume == nil ? 0.55 : 1)
    }

    static func beginSlider(_ point: CGPoint, size: CGSize, mixer: ProcessMixer) -> ((CGPoint) -> Void)? {
        let layout = Layout(height: size.height, selected: mixer.selected, requestedPage: mixer.page)
        guard point.y >= headerHeight, point.y < size.height, point.x >= 32, point.x <= size.width - 78,
              size.width > 110 else { return nil }
        let index = Int((point.y - headerHeight) / rowHeight)
        guard index <= layout.rows.count, index > 0 || mixer.outputVolume != nil else { return nil }
        let process = index == 0 ? nil : layout.rows[index - 1]
        var failed = false
        return { point in
            guard !failed else { return }
            let value = Int((100 * min(1, max(0, (point.x - 32) / (size.width - 110)))).rounded())
            mixer.error = false
            mixer.setWidgetVolume(process, value: value)
            failed = mixer.error
        }
    }

    static func click(_ point: CGPoint, size: CGSize, mixer: ProcessMixer, configure: () -> Void) {
        guard point.y >= 0, point.y < size.height, point.x >= 0, point.x <= size.width else { return }
        if point.y < headerHeight {
            if point.x >= size.width - 28 { configure() }
            return
        }
        let layout = Layout(height: size.height, selected: mixer.selected, requestedPage: mixer.page)
        let index = Int((point.y - headerHeight) / rowHeight)
        if index > layout.rows.count {
            let footerTop = headerHeight + CGFloat(layout.rows.count + 1) * rowHeight
            guard point.y < footerTop + footerHeight else { return }
            if layout.rows.isEmpty { configure() }
            else if layout.pages > 1 {
                mixer.page = min(layout.pages - 1, max(0, layout.page + (point.x < size.width / 2 ? -1 : 1)))
            }
        } else if point.x >= size.width - 24 {
            mixer.toggleMute(index == 0 ? nil : layout.rows[index - 1])
        }
    }
}

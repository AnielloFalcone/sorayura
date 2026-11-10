import AppKit
import CoreAudio
import Observation
import Synchronization

struct AudioProcess: Identifiable, Equatable {
    let id: AudioObjectID
    let pid: pid_t
    let name: String
}

@MainActor @Observable final class ProcessMixer {
    var available: [AudioProcess] = []
    private(set) var selected: [AudioProcess] = []
    private(set) var levels: [AudioObjectID: Int] = [:]
    var error = false
    var page = 0
    @ObservationIgnored var selectionChanged: (() -> Void)?
    @ObservationIgnored private var restoreVolume: [AudioObjectID: Int] = [:]
    private(set) var outputVolume: Int?

    func refreshOutput() {
        let value = OutputVolume.read()
        if value != outputVolume { outputVolume = value }
    }
    @ObservationIgnored private var taps: [AudioObjectID: Any] = [:]
    @ObservationIgnored private var members: [AudioObjectID: [AudioObjectID: pid_t]] = [:]
    @ObservationIgnored private var permissionProbe: Any?
    private(set) var requestingPermission = false

    func requestPermission() async {
        guard #available(macOS 15, *), !requestingPermission else { return }
        requestingPermission = true
        defer { permissionProbe = nil; requestingPermission = false }
        guard let probe = AudioPermissionProbe() else { Self.openAudioPrivacySettings(); return }
        permissionProbe = probe
        try? await Task.sleep(for: .seconds(8))
    }

    static func openAudioPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        guard #available(macOS 15, *) else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        let ids = Self.objects(system, kAudioHardwarePropertyProcessObjectList)
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.bundleURL != nil &&
            $0.processIdentifier > 0 && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let next = apps.compactMap { app -> AudioProcess? in
            guard let name = app.localizedName else { return nil }
            return AudioProcess(id: AudioObjectID(app.processIdentifier), pid: app.processIdentifier, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let byPID = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [AudioObjectID: [AudioObjectID: pid_t]] = [:]
        for id in ids {
            guard let pid = Self.pid(id), pid > 0 else { continue }
            let helper = NSRunningApplication(processIdentifier: pid)
            let path = helper?.executableURL?.path ?? helper?.bundleURL?.path
            let bundleID = helper?.bundleIdentifier ?? Self.string(id, kAudioProcessPropertyBundleID)
            let owner = byPID[pid] ?? apps.filter { app in
                if let root = app.bundleURL?.path, let path { return path.hasPrefix(root + "/") }
                guard let root = app.bundleIdentifier, let bundleID else { return false }
                return bundleID.hasPrefix(root + ".")
            }.max { ($0.bundleURL?.path.count ?? 0) < ($1.bundleURL?.path.count ?? 0) }
            if let owner { groups[AudioObjectID(owner.processIdentifier), default: [:]][id] = pid }
        }
        members = groups
        if available != next { available = next }
        let output = OutputVolume.outputDevice()
        for process in selected {
            if !next.contains(where: { $0.id == process.id && $0.pid == process.pid }) {
                select(process, false)
            } else if let tap = taps[process.id] as? ProcessAudioTap,
                      tap.failed || tap.output != output ||
                      tap.processes != activeMembers(for: process, output: tap.output) {
                taps.removeValue(forKey: process.id)
                levels[process.id] = 100
                error = true
            }
        }
    }

    func select(_ process: AudioProcess, _ enabled: Bool) {
        guard selected.contains(process) != enabled else { return }
        if enabled {
            selected.append(process)
        } else {
            taps.removeValue(forKey: process.id)
            levels.removeValue(forKey: process.id)
            restoreVolume.removeValue(forKey: process.id)
            selected.removeAll { $0.id == process.id }
        }
        selectionChanged?()
    }

    private func activeMembers(for process: AudioProcess, output: AudioDeviceID) -> [AudioObjectID] {
        (members[process.id] ?? [:]).compactMap { id, pid in
            Self.pid(id) == pid && Self.objects(id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput).contains(output) ? id : nil
        }.sorted()
    }

    func set(_ process: AudioProcess, volume: Int) {
        guard #available(macOS 15, *), selected.contains(process) else { return }
        let volume = min(100, max(0, volume))
        error = false
        if volume == 100 {
            taps.removeValue(forKey: process.id)
        } else {
            guard let output = OutputVolume.outputDevice() else { error = true; return }
            let processes = activeMembers(for: process, output: output)
            guard !processes.isEmpty else { error = true; return }
            let current = taps[process.id] as? ProcessAudioTap
            if current?.output != output || current?.processes != processes {
                taps.removeValue(forKey: process.id)
                taps[process.id] = ProcessAudioTap(processes: processes, output: output, volume: volume)
            }
            guard let tap = taps[process.id] as? ProcessAudioTap else {
                levels[process.id] = 100
                error = true
                return
            }
            tap.setVolume(volume)
        }
        levels[process.id] = volume
    }

    func setWidgetVolume(_ process: AudioProcess?, value: Int) {
        if let process {
            if value != (levels[process.id] ?? 100) { set(process, volume: value) }
        } else if value != outputVolume {
            error = !OutputVolume.write(value)
            refreshOutput()
        }
    }

    func toggleMute(_ process: AudioProcess?) {
        let key = process?.id ?? kAudioObjectUnknown
        let current = process.map { levels[$0.id] ?? 100 } ?? outputVolume
        guard let current else { return }
        if current > 0 { restoreVolume[key] = current }
        setWidgetVolume(process, value: current == 0 ? (restoreVolume[key] ?? 50) : 0)
    }

    func stop() { taps.removeAll() }

    private static func pid(_ object: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var result: pid_t = 0
        var size = UInt32(MemoryLayout.size(ofValue: result))
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr ? result : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = address(selector)
        address.mScope = scope
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioObjectID>.stride, size.isMultiple(of: UInt32(MemoryLayout<AudioObjectID>.stride)) else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        let result = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
        return result == noErr ? Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride)) : []
    }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

@available(macOS 15, *)
private final class ProcessAudioTap {
    final class RenderState: Sendable {
        let gain: Atomic<Float>
        let failed = Atomic(false)
        init(_ volume: Int) { gain = Atomic(Float(volume) / 100) }
    }
    private let state: RenderState
    var failed: Bool { state.failed.load(ordering: .relaxed) }
    func setVolume(_ volume: Int) { state.gain.store(Float(volume) / 100, ordering: .relaxed) }
    let output: AudioDeviceID
    let processes: [AudioObjectID]
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioDeviceID(kAudioObjectUnknown)
    private var callback: AudioDeviceIOProcID?
    private var started = false

    @MainActor init?(processes: [AudioObjectID], output: AudioDeviceID, volume: Int) {
        self.output = output
        self.processes = processes
        self.state = RenderState(volume)
        guard let uid = ProcessMixer.string(output, kAudioDevicePropertyDeviceUID) else { return nil }
        // Exclude duplex devices: their physical input must never enter the mix.
        var inputStreams = ProcessMixer.address(kAudioDevicePropertyStreams)
        inputStreams.mScope = kAudioDevicePropertyScopeInput
        var inputSize: UInt32 = 0
        guard !AudioObjectHasProperty(output, &inputStreams) ||
              (AudioObjectGetPropertyDataSize(output, &inputStreams, 0, nil, &inputSize) == noErr && inputSize == 0) else { return nil }
        let description = CATapDescription(processes: processes, deviceUID: uid, stream: 0)
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return nil }
        var address = ProcessMixer.address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: format))
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else { return nil }

        let definition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sorayura Process Audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        guard AudioHardwareCreateAggregateDevice(definition as CFDictionary, &aggregate) == noErr else { return nil }
        guard AudioObjectGetPropertyDataSize(aggregate, &inputStreams, 0, nil, &inputSize) == noErr,
              inputSize == MemoryLayout<AudioStreamID>.size else { return nil }
        var streams = ProcessMixer.address(kAudioDevicePropertyStreams)
        streams.mScope = kAudioDevicePropertyScopeOutput
        var stream = AudioStreamID()
        var streamSize = UInt32(MemoryLayout.size(ofValue: stream))
        guard AudioObjectGetPropertyData(aggregate, &streams, 0, nil, &streamSize, &stream) == noErr, stream != 0 else { return nil }
        var virtualFormat = ProcessMixer.address(kAudioStreamPropertyVirtualFormat)
        var sink = AudioStreamBasicDescription()
        guard AudioObjectGetPropertyData(stream, &virtualFormat, 0, nil, &size, &sink) == noErr,
              sink.mSampleRate == format.mSampleRate, sink.mChannelsPerFrame == format.mChannelsPerFrame,
              sink.mFormatID == format.mFormatID, sink.mBitsPerChannel == format.mBitsPerChannel,
              sink.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }

        let render: AudioDeviceIOBlock = { [state] _, input, _, output, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            let gain = state.gain.load(ordering: .relaxed)
            for index in outputs.indices {
                let destination = outputs[index]
                guard let bytes = destination.mData else { continue }
                let count = Int(destination.mDataByteSize)
                guard inputs.indices.contains(index), inputs[index].mNumberChannels == destination.mNumberChannels,
                      let source = inputs[index].mData, inputs[index].mDataByteSize == destination.mDataByteSize,
                      count.isMultiple(of: MemoryLayout<Float>.stride) else {
                    memset(bytes, 0, count)
                    if count > 0 { state.failed.store(true, ordering: .relaxed) }
                    continue
                }
                let samples = count / MemoryLayout<Float>.stride
                let inSamples = source.assumingMemoryBound(to: Float.self)
                let outSamples = bytes.assumingMemoryBound(to: Float.self)
                for sample in 0..<samples { outSamples[sample] = inSamples[sample] * gain }
            }
        }
        guard AudioDeviceCreateIOProcIDWithBlock(&callback, aggregate, nil, render) == noErr,
              let callback, AudioDeviceStart(aggregate, callback) == noErr else { return nil }
        started = true
    }

    deinit {
        if let callback {
            if started { AudioDeviceStop(aggregate, callback) }
            AudioDeviceDestroyIOProcID(aggregate, callback)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
    }
}

@available(macOS 15, *)
private final class AudioPermissionProbe {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioDeviceID(kAudioObjectUnknown)
    private var callback: AudioDeviceIOProcID?
    private var started = false

    init?() {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { return nil }
        let properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sorayura Audio Access",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        // Starting an input-only tap asks macOS for permission. Discard every sample.
        guard AudioHardwareCreateAggregateDevice(properties as CFDictionary, &aggregate) == noErr,
              AudioDeviceCreateIOProcIDWithBlock(&callback, aggregate, nil, { _, _, _, _, _ in }) == noErr,
              let callback, AudioDeviceStart(aggregate, callback) == noErr else { return nil }
        started = true
    }

    deinit {
        if let callback {
            if started { AudioDeviceStop(aggregate, callback) }
            AudioDeviceDestroyIOProcID(aggregate, callback)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
    }
}

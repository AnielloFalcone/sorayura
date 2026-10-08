import AppKit
import Darwin
import IOKit.ps

func networkRate(_ bytesPerSecond: Double) -> String {
    let bits = max(0, bytesPerSecond) * 8
    if bits >= 1_000_000_000 { return String(format: "%.1f Gbps", locale: Localizer.locale, bits / 1_000_000_000) }
    if bits >= 1_000_000 { return String(format: "%.1f Mbps", locale: Localizer.locale, bits / 1_000_000) }
    if bits >= 1_000 { return String(format: "%.0f Kbps", locale: Localizer.locale, bits / 1_000) }
    return String(format: "%.0f bps", locale: Localizer.locale, bits)
}

struct Metrics {
    var thermal = ProcessInfo.processInfo.thermalState
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var cpu = 0.0
    var memory = 0.0
    var memoryUsed = 0.0
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var memoryApp = 0.0
    var memoryWired = 0.0
    var memoryCompressed = 0.0
    var memoryCached = 0.0
    var swapUsed = 0.0
    var disk = 0.0
    var diskUsed = 0.0
    var diskTotal = 0.0
    var battery: Double? = nil
    var charging = false
    var download = 0.0
    var upload = 0.0
    var uptime = ProcessInfo.processInfo.systemUptime
    var hostname = Host.current().localizedName ?? "MacBook"
    func percentage(_ key: String) -> Double {
        switch key { case "cpu": return cpu; case "memory": return memory; case "disk": return disk; case "battery": return battery ?? 100; case "network": return (download+upload)/1_000_000; default: return 0 }
    }
}

final class MetricsSampler {
    private var diskCache: TimedDiskReadings
    var diskQueries: Int { diskCache.reads }
    init(diskRefreshInterval: TimeInterval = 30) { diskCache = TimedDiskReadings(interval: diskRefreshInterval) }
    private var lastCPU: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var lastNetwork: (received: UInt64, sent: UInt64, time: TimeInterval)?
    func reset() { lastCPU = nil; lastNetwork = nil; diskCache.reset() }
    func sample() -> Metrics {
        var result = Metrics()
        var cpu = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if cpuStatus == KERN_SUCCESS {
            let ticks = cpu.cpu_ticks
            let current = (UInt64(ticks.0), UInt64(ticks.1), UInt64(ticks.2), UInt64(ticks.3))
            if let last = lastCPU {
                let user = UInt32(truncatingIfNeeded:current.0) &- UInt32(truncatingIfNeeded:last.user)
                let system = UInt32(truncatingIfNeeded:current.1) &- UInt32(truncatingIfNeeded:last.system)
                let nice = UInt32(truncatingIfNeeded:current.3) &- UInt32(truncatingIfNeeded:last.nice)
                let idle = UInt32(truncatingIfNeeded:current.2) &- UInt32(truncatingIfNeeded:last.idle)
                let busy = Double(user) + Double(system) + Double(nice)
                let total = busy + Double(idle)
                if total > 0 { result.cpu = busy / total * 100 }
            }
            lastCPU = current
        }
        var vm = vm_statistics64_data_t()
        count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if vmStatus == KERN_SUCCESS {
            let page = Double(getpagesize())
            let active = Double(vm.active_count) * page
            let inactive = Double(vm.inactive_count) * page
            result.memoryWired = Double(vm.wire_count) * page
            result.memoryCompressed = Double(vm.compressor_page_count) * page
            result.memoryApp = Double(vm.internal_page_count - min(vm.internal_page_count, vm.purgeable_count)) * page
            result.memoryCached = inactive
            result.memoryUsed = min(result.memoryTotal, active + result.memoryWired + result.memoryCompressed)
            result.memory = result.memoryTotal > 0 ? result.memoryUsed / result.memoryTotal * 100 : 0
        }
        var swap: xsw_usage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        if sysctl(&mib, 2, &swap, &swapSize, nil, 0) == 0 { result.swapUsed = Double(swap.xsu_used) }
        if let disk = diskCache.sample(at: ProcessInfo.processInfo.systemUptime, read: DiskReadings.read) {
            result.diskTotal = disk.total
            result.diskUsed = disk.used
            result.disk = disk.percentage
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String:Any],
                   let charge = description[kIOPSCurrentCapacityKey] as? Int {
                    result.battery = Double(charge)
                    result.charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
                    break
                }
            }
        }
        var address: UnsafeMutablePointer<ifaddrs>?
        var received: UInt64 = 0
        var sent: UInt64 = 0
        if getifaddrs(&address) == 0 {
            var cursor = address
            while let item = cursor {
                let entry = item.pointee
                if entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                   (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                   let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    received += UInt64(data.pointee.ifi_ibytes)
                    sent += UInt64(data.pointee.ifi_obytes)
                }
                cursor = entry.ifa_next
            }
            freeifaddrs(address)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastNetwork {
            let interval = max(0.01, now - last.time)
            result.download = Double(received >= last.received ? received-last.received : 0) / interval
            result.upload = Double(sent >= last.sent ? sent-last.sent : 0) / interval
        }
        lastNetwork = (received, sent, now)
        result.uptime = now
        return result
    }
}

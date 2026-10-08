// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Sorayura",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sorayura", targets: ["WallpaperNative"])],
    targets: [.executableTarget(name: "WallpaperNative", linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOKit")])]
)

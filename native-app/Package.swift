// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Sorayura",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sorayura", targets: ["WallpaperNative"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(name: "WallpaperNative", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOKit")])]
)

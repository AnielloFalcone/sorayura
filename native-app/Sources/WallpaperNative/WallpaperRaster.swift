import AppKit

/// Static sRGB wallpaper. Sub-LSB, deterministic monochrome noise distributes
/// quantization error so smooth dark gradients do not form visible contour bands.
enum WallpaperRaster {
    static func pixelSize(_ native: CGSize) -> CGSize {
        let ratio = min(1, 4096 / max(1, max(native.width, native.height)))
        return CGSize(width: max(1, (native.width * ratio).rounded()), height: max(1, (native.height * ratio).rounded()))
    }

    static func bitmap(size: CGSize, midnight: Bool) -> NSBitmapImageRep? {
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 24),
              let pixels = bitmap.bitmapData else { return nil }
        bitmap.setProperty(.colorSyncProfileData, withValue: NSColorSpace.sRGB.iccProfileData)
        let base = midnight ? [7.0, 12.0, 22.0] : [16.0, 26.0, 42.0]
        let clouds: [(Double, Double, Double, [Double])] = midnight
            ? [(0.75, 0.18, 0.85, [39, 54, 82])]
            : [(0.18, 0.80, 0.82, [86, 60, 85]), (0.76, 0.19, 0.75, [55, 93, 134])]
        let longest = Double(max(width, height))
        for y in 0..<height {
            for x in 0..<width {
                var r = base[0], g = base[1], b = base[2]
                for (cx, cy, radius, color) in clouds {
                    let dx = Double(x) + 0.5 - Double(width) * cx
                    let dy = Double(y) + 0.5 - Double(height) * cy
                    let t = min(1, sqrt(dx * dx + dy * dy) / (longest * radius))
                    // Zero slope at the center and edge avoids an abrupt falloff.
                    let alpha = 1 - t * t * (3 - 2 * t)
                    r += (color[0] - r) * alpha
                    g += (color[1] - g) * alpha
                    b += (color[2] - b) * alpha
                }
                var hash = UInt32(truncatingIfNeeded: y * width + x) &+ 0x9e3779b9
                hash = (hash ^ (hash >> 16)) &* 0x7feb352d
                hash = (hash ^ (hash >> 15)) &* 0x846ca68b
                hash ^= hash >> 16
                let noise = Double(hash & 0xffff) / 65535 - 0.5
                let offset = y * bitmap.bytesPerRow + x * 3
                pixels[offset] = UInt8(min(255, max(0, floor(r + 0.5 + noise))))
                pixels[offset + 1] = UInt8(min(255, max(0, floor(g + 0.5 + noise))))
                pixels[offset + 2] = UInt8(min(255, max(0, floor(b + 0.5 + noise))))
            }
        }
        return bitmap
    }
}

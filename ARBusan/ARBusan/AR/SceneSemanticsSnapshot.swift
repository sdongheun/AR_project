import UIKit

struct SceneSemanticsSnapshot {
    let overlayImage: UIImage
    let labelData: Data
    let labelWidth: Int
    let labelHeight: Int
    let buildingRatio: Double
    let skyRatio: Double
    let treeRatio: Double
    let roadRatio: Double
    let waterRatio: Double
    let capturedAt: Date

    var diagnosticText: String {
        "Scene Semantics 수신 / building \(Self.percent(buildingRatio)) / sky \(Self.percent(skyRatio)) / tree \(Self.percent(treeRatio)) / road \(Self.percent(roadRatio)) / water \(Self.percent(waterRatio))"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    func evidence(in normalizedPolygon: [CGPoint]) -> SceneSemanticsSpotEvidence? {
        guard labelWidth > 0, labelHeight > 0, !labelData.isEmpty else {
            return nil
        }

        let region = SceneSemanticsSampleRegion(points: normalizedPolygon)
        let data = [UInt8](labelData)
        var sampledCount = 0
        var buildingCount = 0
        var blockingCount = 0
        var skyCount = 0
        var treeCount = 0
        var roadCount = 0
        var waterCount = 0

        let minX = max(0, Int((region.minX * Double(labelWidth - 1)).rounded(.down)))
        let maxX = min(labelWidth - 1, Int((region.maxX * Double(labelWidth - 1)).rounded(.up)))
        let minY = max(0, Int((region.minY * Double(labelHeight - 1)).rounded(.down)))
        let maxY = min(labelHeight - 1, Int((region.maxY * Double(labelHeight - 1)).rounded(.up)))
        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        let xStride = max(1, (maxX - minX) / 48)
        let yStride = max(1, (maxY - minY) / 48)

        for y in stride(from: minY, through: maxY, by: yStride) {
            for x in stride(from: minX, through: maxX, by: xStride) {
                let normalizedPoint = CGPoint(
                    x: CGFloat(Double(x) / Double(max(labelWidth - 1, 1))),
                    y: CGFloat(Double(y) / Double(max(labelHeight - 1, 1)))
                )
                if region.shouldUseWholeBox == false && !Self.polygon(normalizedPolygon, contains: normalizedPoint) {
                    continue
                }

                let label = data[y * labelWidth + x]
                sampledCount += 1

                switch label {
                case 2:
                    buildingCount += 1
                case 1:
                    skyCount += 1
                    blockingCount += 1
                case 3:
                    treeCount += 1
                    blockingCount += 1
                case 4:
                    roadCount += 1
                    blockingCount += 1
                case 11:
                    waterCount += 1
                    blockingCount += 1
                default:
                    break
                }
            }
        }

        guard sampledCount > 0 else {
            return nil
        }

        return SceneSemanticsSpotEvidence(
            buildingCoverageRatio: Double(buildingCount) / Double(sampledCount),
            blockingCoverageRatio: Double(blockingCount) / Double(sampledCount),
            skyCoverageRatio: Double(skyCount) / Double(sampledCount),
            treeCoverageRatio: Double(treeCount) / Double(sampledCount),
            roadCoverageRatio: Double(roadCount) / Double(sampledCount),
            waterCoverageRatio: Double(waterCount) / Double(sampledCount),
            sampledPixelCount: sampledCount
        )
    }

    func buildingLabelAnchor(in normalizedPolygon: [CGPoint]) -> CGPoint? {
        guard labelWidth > 0, labelHeight > 0, !labelData.isEmpty else {
            return nil
        }

        let region = SceneSemanticsSampleRegion(points: normalizedPolygon)
        let data = [UInt8](labelData)
        let minX = max(0, Int((region.minX * Double(labelWidth - 1)).rounded(.down)))
        let maxX = min(labelWidth - 1, Int((region.maxX * Double(labelWidth - 1)).rounded(.up)))
        let minY = max(0, Int((region.minY * Double(labelHeight - 1)).rounded(.down)))
        let maxY = min(labelHeight - 1, Int((region.maxY * Double(labelHeight - 1)).rounded(.up)))
        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        let xStride = max(1, (maxX - minX) / 64)
        let yStride = max(1, (maxY - minY) / 64)
        var buildingCount = 0
        var totalX = 0.0
        var totalY = 0.0

        for y in stride(from: minY, through: maxY, by: yStride) {
            for x in stride(from: minX, through: maxX, by: xStride) {
                let normalizedPoint = CGPoint(
                    x: CGFloat(Double(x) / Double(max(labelWidth - 1, 1))),
                    y: CGFloat(Double(y) / Double(max(labelHeight - 1, 1)))
                )
                if region.shouldUseWholeBox == false && !Self.polygon(normalizedPolygon, contains: normalizedPoint) {
                    continue
                }

                guard data[y * labelWidth + x] == 2 else {
                    continue
                }

                buildingCount += 1
                totalX += Double(normalizedPoint.x)
                totalY += Double(normalizedPoint.y)
            }
        }

        guard buildingCount > 0 else {
            return nil
        }

        return CGPoint(
            x: CGFloat(totalX / Double(buildingCount)),
            y: CGFloat(totalY / Double(buildingCount))
        )
    }

    private static func polygon(_ polygon: [CGPoint], contains point: CGPoint) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }

        var contains = false
        var previousIndex = polygon.count - 1
        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            if crossesY {
                let intersectionX = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < intersectionX {
                    contains.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return contains
    }
}

struct SceneSemanticsSpotEvidence: Equatable {
    let buildingCoverageRatio: Double
    let blockingCoverageRatio: Double
    let skyCoverageRatio: Double
    let treeCoverageRatio: Double
    let roadCoverageRatio: Double
    let waterCoverageRatio: Double
    let sampledPixelCount: Int

    var diagnosticText: String {
        "Scene Semantics 보조 / building \(Self.percent(buildingCoverageRatio)) / 비건물 \(Self.percent(blockingCoverageRatio)) / 샘플 \(sampledPixelCount)px"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct SceneSemanticsSampleRegion {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double
    let shouldUseWholeBox: Bool

    init(points: [CGPoint]) {
        let clampedPoints = points.map {
            CGPoint(
                x: min(1, max(0, $0.x)),
                y: min(1, max(0, $0.y))
            )
        }
        let rawMinX = clampedPoints.map { Double($0.x) }.min() ?? 0.45
        let rawMaxX = clampedPoints.map { Double($0.x) }.max() ?? 0.55
        let rawMinY = clampedPoints.map { Double($0.y) }.min() ?? 0.45
        let rawMaxY = clampedPoints.map { Double($0.y) }.max() ?? 0.55
        let minSize = 0.14
        let expandedX = Self.expand(min: rawMinX, max: rawMaxX, minSize: minSize)
        let expandedY = Self.expand(min: rawMinY, max: rawMaxY, minSize: minSize)

        minX = expandedX.min
        maxX = expandedX.max
        minY = expandedY.min
        maxY = expandedY.max
        shouldUseWholeBox = points.count < 3 || (rawMaxX - rawMinX) < 0.04 || (rawMaxY - rawMinY) < 0.04
    }

    private static func expand(min: Double, max: Double, minSize: Double) -> (min: Double, max: Double) {
        let center = (min + max) / 2
        let halfSize = Swift.max((max - min) / 2, minSize / 2)
        return (
            Swift.max(0, center - halfSize),
            Swift.min(1, center + halfSize)
        )
    }
}

enum SceneSemanticsOverlayRenderer {
    static func render(from semanticImage: CVPixelBuffer) -> SceneSemanticsSnapshot? {
        CVPixelBufferLockBaseAddress(semanticImage, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(semanticImage, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(semanticImage) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(semanticImage)
        let height = CVPixelBufferGetHeight(semanticImage)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(semanticImage)
        guard width > 0, height > 0 else {
            return nil
        }

        let source = baseAddress.assumingMemoryBound(to: UInt8.self)
        var labels = [UInt8](repeating: 0, count: width * height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var buildingCount = 0
        var skyCount = 0
        var treeCount = 0
        var roadCount = 0
        var waterCount = 0

        for y in 0..<height {
            let row = source.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let label = row[x]
                labels[y * width + x] = label
                let color = overlayColor(for: label)
                let outputIndex = (y * width + x) * 4
                rgba[outputIndex] = color.red
                rgba[outputIndex + 1] = color.green
                rgba[outputIndex + 2] = color.blue
                rgba[outputIndex + 3] = color.alpha

                switch label {
                case 2:
                    buildingCount += 1
                case 1:
                    skyCount += 1
                case 3:
                    treeCount += 1
                case 4:
                    roadCount += 1
                case 11:
                    waterCount += 1
                default:
                    break
                }
            }
        }

        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        let totalPixels = Double(width * height)
        return SceneSemanticsSnapshot(
            overlayImage: UIImage(cgImage: cgImage),
            labelData: Data(labels),
            labelWidth: width,
            labelHeight: height,
            buildingRatio: Double(buildingCount) / totalPixels,
            skyRatio: Double(skyCount) / totalPixels,
            treeRatio: Double(treeCount) / totalPixels,
            roadRatio: Double(roadCount) / totalPixels,
            waterRatio: Double(waterCount) / totalPixels,
            capturedAt: Date()
        )
    }

    private static func overlayColor(for label: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        switch label {
        case 2:
            return (0, 122, 255, 120)
        case 1:
            return (255, 59, 48, 120)
        case 3:
            return (255, 214, 10, 120)
        case 4:
            return (142, 142, 147, 110)
        case 11:
            return (90, 200, 250, 120)
        default:
            return (0, 0, 0, 0)
        }
    }
}

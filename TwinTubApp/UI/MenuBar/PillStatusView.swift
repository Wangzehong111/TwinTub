import SwiftUI
import AppKit

struct PillStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: SessionStore.GlobalStatus
    @State private var spinStep: Int = 0

    private var isProcessing: Bool {
        if case .processing = status { return true }
        return false
    }

    private var hasWaiting: Bool {
        if case .processing(let hasWaiting) = status { return hasWaiting }
        return false
    }

    private var waitingCount: Int {
        if case .waiting(let count) = status { return count }
        return 0
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: statusImage)
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .accessibilityLabel(accessibilityStatus)
                .task(id: isProcessing) {
                    guard isProcessing else {
                        spinStep = 0
                        return
                    }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { break }
                        spinStep = (spinStep + 1) % 30
                    }
                }

            // 当 processing 同时存在 waiting 时显示红点徽章
            if hasWaiting {
                waitingBadge(count: max(1, waitingCount))
            } else if waitingCount > 1 {
                waitingBadge(count: waitingCount)
            }
        }
    }

    private func waitingBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 2.5)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(Color.red)
            )
            .offset(x: 4, y: -4)
    }

    private var statusImage: NSImage {
        if isProcessing {
            let angle = Double(spinStep) * 12.0
            return MenuBarIconRenderer.render(
                status: status, colorScheme: colorScheme, rotationAngle: angle
            )
        }
        return MenuBarIconRenderer.render(status: status, colorScheme: colorScheme)
    }

    private var accessibilityStatus: String {
        switch status {
        case .idle:
            return "TwinTub Idle"
        case .processing(let hasWaiting):
            if hasWaiting {
                return "TwinTub Processing (with waiting sessions)"
            }
            return "TwinTub Processing"
        case .waiting(let count):
            if count > 1 {
                return "TwinTub Waiting for Input (\(count) sessions)"
            }
            return "TwinTub Waiting for Input"
        case .done:
            return "TwinTub Done"
        }
    }
}

private enum MenuBarIconRenderer {
    private static let iconSize: CGFloat = 18
    private static let designSize: CGFloat = 24
    private static let scale: CGFloat = iconSize / designSize

    // MARK: - Icon Cache (thread-safe via actor)
    private enum CacheKey: String, CaseIterable {
        case idleDark, idleLight
        case waitingDark, waitingLight
        case doneDark, doneLight
        case processingDark, processingLight
    }

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var imageCache: [CacheKey: NSImage] = [:]

    private static func getCached(_ key: CacheKey) -> NSImage? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return imageCache[key]
    }

    private static func setCached(_ key: CacheKey, image: NSImage) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        imageCache[key] = image
    }

    static func render(
        status: SessionStore.GlobalStatus,
        colorScheme: ColorScheme,
        rotationAngle: Double = 0
    ) -> NSImage {
        let isDark = colorScheme == .dark

        // For processing with rotation, we still need to render dynamically
        if case .processing = status, rotationAngle != 0 {
            return renderProcessingWithRotation(rotationAngle: rotationAngle, colorScheme: colorScheme)
        }

        // Determine cache key and render function
        let cacheKey: CacheKey
        let renderFn: (ColorScheme) -> NSImage

        switch status {
        case .idle:
            cacheKey = isDark ? .idleDark : .idleLight
            renderFn = renderIdleImage
        case .waiting:
            cacheKey = isDark ? .waitingDark : .waitingLight
            renderFn = renderWaitingImage
        case .done:
            cacheKey = isDark ? .doneDark : .doneLight
            renderFn = renderDoneImage
        case .processing:
            cacheKey = isDark ? .processingDark : .processingLight
            renderFn = { renderProcessingImage(colorScheme: $0, rotationAngle: 0) }
        }

        // Check cache
        if let cached = getCached(cacheKey) { return cached }

        // Render and cache
        let image = renderFn(colorScheme)
        setCached(cacheKey, image: image)
        return image
    }

    private static func renderIdleImage(colorScheme: ColorScheme) -> NSImage {
        NSImage(size: NSSize(width: iconSize, height: iconSize), flipped: true) { _ in
            let color = strokeColor(for: .idle, colorScheme: colorScheme)
            drawChevron(color: color, lineWidth: 2.5 * scale)
            drawIdle(color: color)
            return true
        }
    }

    private static func renderWaitingImage(colorScheme: ColorScheme) -> NSImage {
        NSImage(size: NSSize(width: iconSize, height: iconSize), flipped: true) { _ in
            let color = strokeColorForWaiting(colorScheme: colorScheme)
            drawChevron(color: color, lineWidth: 2.5 * scale)
            drawWaiting(color: color)
            return true
        }
    }

    private static func renderDoneImage(colorScheme: ColorScheme) -> NSImage {
        NSImage(size: NSSize(width: iconSize, height: iconSize), flipped: true) { _ in
            let color = strokeColorForDone(colorScheme: colorScheme)
            drawChevron(color: color, lineWidth: 2.5 * scale)
            drawDone(color: color)
            return true
        }
    }

    private static func renderProcessingImage(colorScheme: ColorScheme, rotationAngle: Double) -> NSImage {
        NSImage(size: NSSize(width: iconSize, height: iconSize), flipped: true) { _ in
            let color = strokeColorForProcessing(colorScheme: colorScheme)
            drawChevron(color: color, lineWidth: 2.5 * scale)
            drawProcessing(color: color, rotationAngle: rotationAngle)
            return true
        }
    }

    private static func renderProcessingWithRotation(rotationAngle: Double, colorScheme: ColorScheme) -> NSImage {
        return renderProcessingImage(colorScheme: colorScheme, rotationAngle: rotationAngle)
    }

    // MARK: - Theme Change Notification
    static func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        imageCache.removeAll(keepingCapacity: true)
    }

    private static func strokeColor(for status: SessionStore.GlobalStatus, colorScheme: ColorScheme) -> NSColor {
        switch status {
        case .idle:
            return strokeColorForIdle(colorScheme: colorScheme)
        case .processing:
            return strokeColorForProcessing(colorScheme: colorScheme)
        case .waiting:
            return strokeColorForWaiting(colorScheme: colorScheme)
        case .done:
            return strokeColorForDone(colorScheme: colorScheme)
        }
    }

    private static func strokeColorForIdle(colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.96)
            : NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.92)
    }

    private static func strokeColorForProcessing(colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.28, alpha: 1.0)
            : NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.02, alpha: 1.0)
    }

    private static func strokeColorForWaiting(colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.42, alpha: 1.0)
            : NSColor(calibratedRed: 0.82, green: 0.29, blue: 0.40, alpha: 1.0)
    }

    private static func strokeColorForDone(colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark
            ? NSColor(calibratedRed: 0.49, green: 0.99, blue: 0.0, alpha: 1.0)
            : NSColor(calibratedRed: 0.02, green: 0.59, blue: 0.41, alpha: 1.0)
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x * scale, y: y * scale)
    }

    private static func strokePath(_ points: [NSPoint], color: NSColor, lineWidth: CGFloat, dashed: Bool = false) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.lineWidth = max(1.0, lineWidth)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if dashed {
            let pattern: [CGFloat] = [2 * scale, 2 * scale]
            path.setLineDash(pattern, count: pattern.count, phase: 0)
        }
        color.setStroke()
        path.stroke()
    }

    private static func fillCircle(center: NSPoint, radius: CGFloat, color: NSColor) {
        let oval = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        color.setFill()
        oval.fill()
    }

    private static func drawChevron(color: NSColor, lineWidth: CGFloat) {
        strokePath([p(4, 17), p(10, 11), p(4, 5)], color: color, lineWidth: lineWidth)
    }

    private static func drawIdle(color: NSColor) {
        strokePath([p(13, 19), p(21, 19)], color: color, lineWidth: 2.5 * scale)
        fillCircle(center: p(17, 11), radius: max(1.1, 2 * scale), color: color)
    }

    private static func drawProcessing(color: NSColor, rotationAngle: Double) {
        let base = NSColor(
            calibratedRed: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: max(0.45, color.alphaComponent * 0.55)
        )
        strokePath([p(12, 19), p(20, 19)], color: base, lineWidth: 2.4 * scale, dashed: true)

        let cx = 16 * scale
        let cy = 10 * scale

        NSGraphicsContext.current?.saveGraphicsState()
        let xform = NSAffineTransform()
        xform.translateX(by: cx, yBy: cy)
        xform.rotate(byDegrees: CGFloat(rotationAngle))
        xform.translateX(by: -cx, yBy: -cy)
        xform.concat()

        strokePath([p(16, 6), p(16, 14)], color: color, lineWidth: 2.0 * scale)
        strokePath([p(12, 10), p(20, 10)], color: color, lineWidth: 2.0 * scale)

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func drawWaiting(color: NSColor) {
        strokePath([p(12, 18), p(18, 18)], color: color, lineWidth: 2.0 * scale)
        fillCircle(center: p(16, 5), radius: max(0.9, 1.4 * scale), color: color)
        fillCircle(center: p(19, 8), radius: max(0.9, 1.4 * scale), color: color)
    }

    private static func drawDone(color: NSColor) {
        strokePath([p(12, 19), p(20, 19)], color: color, lineWidth: 2.0 * scale)
        strokePath([p(14.8, 10.6), p(16.5, 12.6), p(19.7, 8.8)], color: color, lineWidth: 2.0 * scale)
    }
}

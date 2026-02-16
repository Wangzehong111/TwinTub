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

    var body: some View {
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
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { break }
                    spinStep = (spinStep + 1) % 30
                }
            }
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
            return "Beacon Idle"
        case .processing:
            return "Beacon Processing"
        case .waiting:
            return "Beacon Waiting for Input"
        case .done:
            return "Beacon Done"
        }
    }
}

private enum MenuBarIconRenderer {
    private static let iconSize: CGFloat = 18
    private static let designSize: CGFloat = 24
    private static let scale: CGFloat = iconSize / designSize

    static func render(
        status: SessionStore.GlobalStatus,
        colorScheme: ColorScheme,
        rotationAngle: Double = 0
    ) -> NSImage {
        NSImage(size: NSSize(width: iconSize, height: iconSize), flipped: true) { _ in
            let color = strokeColor(for: status, colorScheme: colorScheme)
            drawChevron(color: color, lineWidth: 2.5 * scale)

            switch status {
            case .idle:
                drawIdle(color: color)
            case .processing:
                drawProcessing(color: color, rotationAngle: rotationAngle)
            case .waiting:
                drawWaiting(color: color)
            case .done:
                drawDone(color: color)
            }
            return true
        }
    }

    private static func strokeColor(for status: SessionStore.GlobalStatus, colorScheme: ColorScheme) -> NSColor {
        switch status {
        case .idle:
            return colorScheme == .dark
                ? NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.96)
                : NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.92)
        case .processing:
            return colorScheme == .dark
                ? NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.28, alpha: 1.0)
                : NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.02, alpha: 1.0)
        case .waiting:
            return colorScheme == .dark
                ? NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.42, alpha: 1.0)
                : NSColor(calibratedRed: 0.82, green: 0.29, blue: 0.40, alpha: 1.0)
        case .done:
            return colorScheme == .dark
                ? NSColor(calibratedRed: 0.49, green: 0.99, blue: 0.0, alpha: 1.0)
                : NSColor(calibratedRed: 0.02, green: 0.59, blue: 0.41, alpha: 1.0)
        }
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

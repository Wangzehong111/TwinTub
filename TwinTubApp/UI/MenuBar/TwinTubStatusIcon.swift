import SwiftUI

// Menu bar icon based on icon_design.html Concept C (Terminal + TwinTub).
struct TwinTubStatusIcon: View {
    let status: SessionStore.GlobalStatus
    let color: Color

    var body: some View {
        Group {
            if case .processing = status {
                TimelineView(.animation) { context in
                    iconCanvas(spinDate: context.date)
                }
            } else {
                iconCanvas(spinDate: nil)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func iconCanvas(spinDate: Date?) -> some View {
        GeometryReader { geometry in
            let metrics = IconMetrics(size: geometry.size)
            let baseStroke = StrokeStyle(
                lineWidth: metrics.lineWidth(2.5, minimum: 1.3),
                lineCap: .round,
                lineJoin: .round
            )

            ZStack {
                terminalChevron(metrics)
                    .stroke(color, style: baseStroke)

                switch status {
                case .processing:
                    processingBody(metrics: metrics, baseStroke: baseStroke, spinDate: spinDate)
                case .waiting:
                    waitingBody(metrics: metrics)
                case .idle:
                    idleBody(metrics: metrics)
                case .done:
                    doneBody(metrics: metrics)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private struct IconMetrics {
        let size: CGSize

        var scale: CGFloat {
            max(0.1, min(size.width, size.height) / 24.0)
        }

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scale, y: y * scale)
        }

        func x(_ value: CGFloat) -> CGFloat {
            value * scale
        }

        func y(_ value: CGFloat) -> CGFloat {
            value * scale
        }

        func lineWidth(_ base: CGFloat, minimum: CGFloat) -> CGFloat {
            max(minimum, base * scale)
        }
    }

    private func terminalChevron(_ metrics: IconMetrics) -> Path {
        Path { path in
            path.move(to: metrics.point(4, 17))
            path.addLine(to: metrics.point(10, 11))
            path.addLine(to: metrics.point(4, 5))
        }
    }

    @ViewBuilder
    private func idleBody(metrics: IconMetrics) -> some View {
        Path { path in
            path.move(to: metrics.point(13, 19))
            path.addLine(to: metrics.point(21, 19))
        }
        .stroke(color, style: StrokeStyle(lineWidth: metrics.lineWidth(2.5, minimum: 1.3), lineCap: .round))

        Circle()
            .fill(color)
            .frame(width: metrics.x(4), height: metrics.y(4))
            .position(x: metrics.x(17), y: metrics.y(11))
    }

    private func spinAngle(from date: Date?) -> Double {
        guard let date = date else { return 0 }
        let seconds = date.timeIntervalSinceReferenceDate
        return (seconds.truncatingRemainder(dividingBy: 3.0) / 3.0) * 360.0
    }

    @ViewBuilder
    private func processingBody(metrics: IconMetrics, baseStroke: StrokeStyle, spinDate: Date?) -> some View {
        Path { path in
            path.move(to: metrics.point(12, 19))
            path.addLine(to: metrics.point(20, 19))
        }
        .stroke(
            color.opacity(0.5),
            style: StrokeStyle(
                lineWidth: baseStroke.lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: [2, 2]
            )
        )

        ZStack {
            Path { path in
                path.move(to: metrics.point(16, 6))
                path.addLine(to: metrics.point(16, 14))
            }
            .stroke(color, style: StrokeStyle(lineWidth: metrics.lineWidth(2.0, minimum: 1.1), lineCap: .round))

            Path { path in
                path.move(to: metrics.point(12, 10))
                path.addLine(to: metrics.point(20, 10))
            }
            .stroke(color, style: StrokeStyle(lineWidth: metrics.lineWidth(2.0, minimum: 1.1), lineCap: .round))
        }
        .rotationEffect(
            .degrees(spinAngle(from: spinDate)),
            anchor: UnitPoint(
                x: metrics.size.width > 0 ? metrics.x(16) / metrics.size.width : 0.5,
                y: metrics.size.height > 0 ? metrics.y(10) / metrics.size.height : 0.5
            )
        )
    }

    @ViewBuilder
    private func waitingBody(metrics: IconMetrics) -> some View {
        Path { path in
            path.move(to: metrics.point(12, 18))
            path.addLine(to: metrics.point(18, 18))
        }
        .stroke(color, style: StrokeStyle(lineWidth: metrics.lineWidth(2.0, minimum: 1.1), lineCap: .round))

        Circle()
            .fill(color)
            .frame(width: metrics.x(2.8), height: metrics.y(2.8))
            .position(x: metrics.x(16), y: metrics.y(5))

        Circle()
            .fill(color)
            .frame(width: metrics.x(2.8), height: metrics.y(2.8))
            .position(x: metrics.x(19), y: metrics.y(8))
    }

    @ViewBuilder
    private func doneBody(metrics: IconMetrics) -> some View {
        Path { path in
            path.move(to: metrics.point(12, 19))
            path.addLine(to: metrics.point(20, 19))
        }
        .stroke(color, style: StrokeStyle(lineWidth: metrics.lineWidth(2.0, minimum: 1.1), lineCap: .round))

        Path { path in
            path.move(to: metrics.point(14.8, 10.6))
            path.addLine(to: metrics.point(16.5, 12.6))
            path.addLine(to: metrics.point(19.7, 8.8))
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: metrics.lineWidth(2.0, minimum: 1.1),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
}

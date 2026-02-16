import SwiftUI

// Icon geometry adapted from Lucide icons (ISC License):
// https://lucide.dev/icons/circle
// https://lucide.dev/icons/loader-circle
// https://lucide.dev/icons/triangle-alert
// https://lucide.dev/icons/circle-check-big
struct BeaconStatusIcon: View {
    let status: SessionStore.GlobalStatus
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let sx = max(0.1, geometry.size.width / 24)
            let sy = max(0.1, geometry.size.height / 24)
            let style = StrokeStyle(lineWidth: max(1.35, min(sx, sy) * 1.8), lineCap: .round, lineJoin: .round)
            let paths = iconPaths(sx: sx, sy: sy, status: status)

            ZStack {
                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                    path.stroke(color, style: style)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func iconPaths(sx: CGFloat, sy: CGFloat, status: SessionStore.GlobalStatus) -> [Path] {
        switch status {
        case .idle:
            return [
                Circle().path(in: CGRect(x: 2 * sx, y: 2 * sy, width: 20 * sx, height: 20 * sy))
            ]

        case .processing:
            return [
                Path { path in
                    path.move(to: CGPoint(x: 21 * sx, y: 12 * sy))
                    path.addCurve(
                        to: CGPoint(x: 14.781 * sx, y: 3.44 * sy),
                        control1: CGPoint(x: 21 * sx, y: 7.03 * sy),
                        control2: CGPoint(x: 18.52 * sx, y: 4.09 * sy)
                    )
                }
            ]

        case .waiting:
            return [
                Path { path in
                    path.move(to: CGPoint(x: 21.73 * sx, y: 18 * sy))
                    path.addLine(to: CGPoint(x: 13.73 * sx, y: 4 * sy))
                    path.addCurve(
                        to: CGPoint(x: 10.25 * sx, y: 4 * sy),
                        control1: CGPoint(x: 13.03 * sx, y: 2.77 * sy),
                        control2: CGPoint(x: 10.95 * sx, y: 2.77 * sy)
                    )
                    path.addLine(to: CGPoint(x: 2.25 * sx, y: 18 * sy))
                    path.addCurve(
                        to: CGPoint(x: 4 * sx, y: 21 * sy),
                        control1: CGPoint(x: 1.54 * sx, y: 19.23 * sy),
                        control2: CGPoint(x: 2.43 * sx, y: 21 * sy)
                    )
                    path.addLine(to: CGPoint(x: 20 * sx, y: 21 * sy))
                    path.addCurve(
                        to: CGPoint(x: 21.73 * sx, y: 18 * sy),
                        control1: CGPoint(x: 21.57 * sx, y: 21 * sy),
                        control2: CGPoint(x: 22.44 * sx, y: 19.23 * sy)
                    )
                },
                Path { path in
                    path.move(to: CGPoint(x: 12 * sx, y: 9 * sy))
                    path.addLine(to: CGPoint(x: 12 * sx, y: 13 * sy))
                },
                Path { path in
                    path.move(to: CGPoint(x: 12 * sx, y: 17 * sy))
                    path.addLine(to: CGPoint(x: 12.01 * sx, y: 17 * sy))
                }
            ]

        case .done:
            return [
                Path { path in
                    path.move(to: CGPoint(x: 21.801 * sx, y: 10 * sy))
                    path.addCurve(
                        to: CGPoint(x: 17 * sx, y: 3.335 * sy),
                        control1: CGPoint(x: 20.96 * sx, y: 7.35 * sy),
                        control2: CGPoint(x: 19.26 * sx, y: 4.98 * sy)
                    )
                    path.addCurve(
                        to: CGPoint(x: 2 * sx, y: 12 * sy),
                        control1: CGPoint(x: 13.08 * sx, y: 1.05 * sy),
                        control2: CGPoint(x: 7.74 * sx, y: 1.79 * sy)
                    )
                    path.addCurve(
                        to: CGPoint(x: 12 * sx, y: 22 * sy),
                        control1: CGPoint(x: 2 * sx, y: 17.52 * sy),
                        control2: CGPoint(x: 6.48 * sx, y: 22 * sy)
                    )
                    path.addCurve(
                        to: CGPoint(x: 22 * sx, y: 12 * sy),
                        control1: CGPoint(x: 17.52 * sx, y: 22 * sy),
                        control2: CGPoint(x: 22 * sx, y: 17.52 * sy)
                    )
                },
                Path { path in
                    path.move(to: CGPoint(x: 9 * sx, y: 11 * sy))
                    path.addLine(to: CGPoint(x: 12 * sx, y: 14 * sy))
                    path.addLine(to: CGPoint(x: 22 * sx, y: 4 * sy))
                }
            ]
        }
    }
}

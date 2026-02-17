// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwinTub",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TwinTubApp", targets: ["TwinTubApp"])
    ],
    targets: [
        .executableTarget(
            name: "TwinTubApp",
            path: "TwinTubApp"
        ),
        .testTarget(
            name: "TwinTubTests",
            dependencies: ["TwinTubApp"],
            path: "TwinTubTests"
        )
    ]
)

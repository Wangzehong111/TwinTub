// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Beacon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BeaconApp", targets: ["BeaconApp"])
    ],
    targets: [
        .executableTarget(
            name: "BeaconApp",
            path: "BeaconApp"
        ),
        .testTarget(
            name: "BeaconTests",
            dependencies: ["BeaconApp"],
            path: "BeaconTests"
        )
    ]
)

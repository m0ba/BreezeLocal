// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BreezeLocal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BreezeLocal", targets: ["BreezeLocal"])
    ],
    targets: [
        .executableTarget(
            name: "BreezeLocal",
            path: "Sources/BreezeLocal"
        )
    ]
)

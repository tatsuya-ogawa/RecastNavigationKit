// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RecastNavigationKit",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "RecastNavigationKit", targets: ["RecastNavigationKit"])
    ],
    targets: [
        .binaryTarget(
            name: "Recast",
            url: "https://github.com/tatsuya-ogawa/RecastNavigationKit/releases/download/v0.1/Recast.xcframework.zip",
            checksum: "2fa4ed6eeac11f33b4f0f972258adfe5bb3dbfe86118fced68e3e7eb247cc2c6"
        ),
        .binaryTarget(
            name: "Detour",
            url: "https://github.com/tatsuya-ogawa/RecastNavigationKit/releases/download/v0.1/Detour.xcframework.zip",
            checksum: "fc6351928f797ab97c95e016fce92477ec1a1df8297f4de39998252cbad6ce5b"
        ),
        .target(
            name: "RecastNavigationObjC",
            dependencies: ["Recast", "Detour"],
            path: "RecastNavigationKit/Sources/RecastNavigationObjC",
            cxxSettings: [
                .unsafeFlags(["-std=c++20"])
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "RecastNavigationKit",
            dependencies: ["RecastNavigationObjC"],
            path: "RecastNavigationKit/Sources/RecastNavigationKit"
        )
    ]
)

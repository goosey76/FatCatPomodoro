// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FatCatPomodoro",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FatCatPomodoro", targets: ["FatCatPomodoro"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FatCatPomodoro",
            dependencies: [],
            path: "Sources/FatCatPomodoro",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/FatCatPomodoro/Info.plist"
                ])
            ]
        )
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RoomRedesign",
    
    platforms: [
        .iOS("18.0")  // ✅ Correct!
    ],
    
    products: [
        .library(
            name: "RoomRedesign",
            targets: ["RoomRedesign"]),
    ],
    targets: [
        .target(
            name: "RoomRedesign",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)

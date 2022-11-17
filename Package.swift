// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OfflineRequestManager",
    platforms: [
    	.iOS(.v13),
    ],
    products: [
        .library(
            name: "OfflineRequestManager",
            targets: ["OfflineRequestManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.6.1"))
    ],
    targets: [
        .target(
            name: "OfflineRequestManager",
            dependencies: [
                "Alamofire"
            ],
            path: "OfflineRequestManager",
            sources: ["Classes"]
        )
    ]
)

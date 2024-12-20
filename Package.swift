// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "party",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "party",
            targets: ["party"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.19.0")
    ],
    targets: [
        .target(
            name: "party",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestoreSwift", package: "firebase-ios-sdk")
            ]),
        .testTarget(
            name: "partyTests",
            dependencies: ["party"]),
    ]
) 
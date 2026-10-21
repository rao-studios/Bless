// swift-tools-version: 6.4
// Created by Ritesh Pakala on 10/20/26.
// Copyright © 2026 Rao Studios LLC.
//
// WHAT: The Bless playground, a package of its own: a macOS SwiftUI app that puts a patient, a
//       model and a reviewer in one window against one Gate, so the human-in-the-loop pattern
//       can be watched end to end against Mistral (or any OpenAI-compatible layer, or an offline
//       fake). Examples/run.sh builds it (release) and runs it; from Xcode, open this manifest
//       and Run. Examples/README.md is the run sheet.
// PIN:  Bless by path. Two targets: BlessPlaygroundKit (the session, the draft tee, keys, the
//       reviewer's identity, scenarios and the fake model: Foundation, Observation and Bless only,
//       so the tests drive the whole flow with no window and no network) and BlessPlayground (the
//       SwiftUI app). The app's Info.plist is linked into the binary (__TEXT,__info_plist), so the
//       bare build product is a real app with a bundle id and a menu-bar name, and no .app wrapper
//       is needed (the recipe Leviathan, VisionAX and Mary use on this Mac). unsafeFlags is allowed
//       because this package is never a dependency. macOS 26 like the family's other playgrounds;
//       Bless itself is macOS 15.
import PackageDescription

let package = Package(
    name: "BlessPlayground",
    platforms: [.macOS("26.0")],
    dependencies: [.package(path: "..")],
    targets: [
        .target(
            name: "BlessPlaygroundKit",
            dependencies: [
                .product(name: "Bless", package: "Bless"),
                .product(name: "BlessProviders", package: "Bless"),
            ]
        ),
        .executableTarget(
            name: "BlessPlayground",
            dependencies: [
                "BlessPlaygroundKit",
                .product(name: "Bless", package: "Bless"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Support/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "BlessPlaygroundTests",
            dependencies: [
                "BlessPlaygroundKit",
                .product(name: "Bless", package: "Bless"),
            ]
        ),
    ]
)

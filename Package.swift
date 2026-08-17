// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ImageAutonamer",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "ImageAutonamerKit", targets: ["ImageAutonamerKit"]),
    .executable(name: "ImageAutonamerMac", targets: ["ImageAutonamerMac"]),
  ],
  targets: [
    .target(
      name: "ImageAutonamerKit",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("PDFKit"),
        .linkedFramework("Vision"),
      ]
    ),
    .executableTarget(
      name: "ImageAutonamerMac",
      dependencies: ["ImageAutonamerKit"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("PDFKit"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("Vision"),
      ]
    ),
    .testTarget(
      name: "ImageAutonamerKitTests",
      dependencies: ["ImageAutonamerKit"]
    ),
  ]
)

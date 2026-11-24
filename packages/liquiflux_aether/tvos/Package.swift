// swift-tools-version: 5.9
//
// Liquiflux's Apple TV player. flutter-tvos puts this package in the app's generated plugin
// package (FlutterGeneratedPluginSwiftPackage); ../FlutterFramework is its sibling there.
import PackageDescription

let package = Package(
  name: "liquiflux_aether",
  platforms: [
    .tvOS("18.0"),
  ],
  products: [
    .library(name: "liquiflux-aether", targets: ["liquiflux_aether"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
    // One release, never a range: an engine update is a deliberate change here.
    .package(url: "https://github.com/superuser404notfound/AetherEngine", exact: "7.73.0"),
  ],
  targets: [
    .target(
      name: "liquiflux_aether",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        .product(name: "AetherEngine", package: "AetherEngine"),
      ],
      path: "Classes"
    ),
  ]
)

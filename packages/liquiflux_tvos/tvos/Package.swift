// swift-tools-version: 5.9
//
// Liquiflux's Apple TV platform plugin. flutter-tvos puts this package in the app's generated
// plugin package; ../FlutterFramework is its sibling there.
import PackageDescription

let package = Package(
  name: "liquiflux_tvos",
  platforms: [
    .tvOS("18.0"),
  ],
  products: [
    .library(name: "liquiflux-tvos", targets: ["liquiflux_tvos"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "liquiflux_tvos",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ],
      path: "Classes"
    ),
  ]
)

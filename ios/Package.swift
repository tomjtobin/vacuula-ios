// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VacuulaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "VacuulaCore", targets: ["VacuulaCore"])],
    targets: [
        .target(name: "VacuulaCore"),
        .testTarget(name: "VacuulaCoreTests", dependencies: ["VacuulaCore"], resources: [.copy("Fixtures")])
    ]
)

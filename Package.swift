// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tilik-Cloudkit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "Tilik-Cloudkit", targets: ["TilikCloudkit"])],
    targets: [.target(name: "TilikCloudkit")],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Textline", platforms: [.macOS(.v14)], products: [.executable(name: "Textline", targets: ["Textline"])], targets: [.executableTarget(name: "Textline")])

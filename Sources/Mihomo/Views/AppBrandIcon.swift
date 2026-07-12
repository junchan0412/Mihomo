import AppKit
import SwiftUI

struct AppBrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat

    var body: some View {
        Group {
            if let image = brandImage {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .resizable().scaledToFit().padding(size * 0.18)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Mihomo")
    }

    private var brandImage: NSImage? {
        let name = colorScheme == .dark ? "AppIcon-Dark" : "AppIcon-Light"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

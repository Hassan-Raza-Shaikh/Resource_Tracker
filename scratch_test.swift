import SwiftUI

extension View {
    func glassCardStyle() -> some View {
        GlassEffectContainer {
            self
                .padding(14)
        }
        .glassEffect()
    }
}

struct TestView: View {
    var body: some View {
        Text("Test")
            .glassCardStyle()
    }
}

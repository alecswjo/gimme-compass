import SwiftUI

@main
struct GimmeApp: App {
    @State private var model = CompassViewModel.live()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

import SwiftUI

@main
@MainActor
struct FPVHUDApp: App {
    @StateObject private var viewModel = FPVHUDViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
        }
    }
}

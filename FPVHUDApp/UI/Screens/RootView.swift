import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: FPVHUDViewModel
    @State private var presentationMode: HUDPresentationMode = .drive

    var body: some View {
        ZStack {
            switch presentationMode {
            case .drive:
                FPVHUDView(
                    telemetry: viewModel.telemetryDisplay,
                    motion: viewModel.motion,
                    settings: viewModel.settings,
                    headTrackingDisplay: viewModel.headTrackingDisplay,
                    onOpenDebug: {
                        presentationMode = .debug
                    }
                )
            case .debug:
                DebugHUDView(
                    viewModel: viewModel,
                    onOpenSettings: {
                        viewModel.isSettingsPresented = true
                    },
                    onExit: {
                        presentationMode = .drive
                    }
                )
            }
        }
        .fpvStatusBarHidden()
        .onAppear {
            viewModel.startServicesIfNeeded()
        }
        .fullScreenCover(isPresented: $viewModel.isSettingsPresented) {
            SettingsPanelView(viewModel: viewModel)
        }
    }
}

private enum HUDPresentationMode: Equatable {
    case drive
    case debug
}

private extension View {
    @ViewBuilder
    func fpvStatusBarHidden() -> some View {
        #if os(iOS)
        self.statusBarHidden(true)
        #else
        self
        #endif
    }
}

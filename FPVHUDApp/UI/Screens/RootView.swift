import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: FPVHUDViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FPVHUDView(
                telemetry: viewModel.telemetry,
                motion: viewModel.motion,
                settings: viewModel.settings,
                headTrackingSenderStatus: viewModel.headTrackingSenderStatus
            )

            Button {
                viewModel.isSettingsPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HUDIconButtonStyle())
            .padding(.top, 74)
            .padding(.trailing, 16)
            .accessibilityLabel("Settings")
        }
        .fpvStatusBarHidden()
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsPanelView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
    }
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

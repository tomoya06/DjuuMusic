import SwiftUI

enum AppTab: Hashable {
    case home, library, me
}

struct RootView: View {
    @Environment(PlayerModel.self) private var player
    @State private var tab: AppTab = .home

    var body: some View {
        @Bindable var player = player

        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("主页", systemImage: "house.fill") }
                .tag(AppTab.home)

            LibraryView()
                .tabItem { Label("曲库", systemImage: "music.note.list") }
                .tag(AppTab.library)

            MeView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(AppTab.me)
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .djuuBottomAccessory(isEnabled: player.hasCurrent && !player.showFullScreen) {
            MiniPlayerBar()
        }
        // 播放页用大档位 sheet 呈现：原生支持下滑收起（抽屉式），带拖拽指示条。
        .sheet(isPresented: $player.showFullScreen) {
            NowPlayingView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// iOS 26.1+ 用系统 isEnabled 控制迷你条显隐；更早版本直接不挂 accessory，
/// 避免 tabViewBottomAccessory 在内容为空时仍渲染空玻璃壳。
private extension View {
    @ViewBuilder
    func djuuBottomAccessory<Content: View>(isEnabled: Bool,
                                            @ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: isEnabled, content: content)
        } else {
            if isEnabled {
                self.tabViewBottomAccessory(content: content)
            } else {
                self
            }
        }
    }
}

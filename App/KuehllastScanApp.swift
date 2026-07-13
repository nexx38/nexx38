import SwiftUI

@main
struct KuehllastScanApp: App {
    @StateObject private var store = RoomStore()

    var body: some Scene {
        WindowGroup {
            RoomListView()
                .environmentObject(store)
        }
    }
}

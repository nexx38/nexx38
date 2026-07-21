import SwiftUI

@main
struct LastScanApp: App {
    @StateObject private var store = RoomStore()

    var body: some Scene {
        WindowGroup {
            RoomListView()
                .environmentObject(store)
        }
    }
}

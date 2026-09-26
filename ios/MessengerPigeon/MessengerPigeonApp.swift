import SwiftUI
import UIKit

final class PrivacyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier identifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        identifier != .keyboard
    }
}

@main
struct MessengerPigeonApp: App {
    @UIApplicationDelegateAdaptor(PrivacyAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup { RootView().tint(.pigeonGreen) }
    }
}

extension Color {
    static let pigeonGreen = Color(red: 0.16, green: 0.43, blue: 0.31)
}


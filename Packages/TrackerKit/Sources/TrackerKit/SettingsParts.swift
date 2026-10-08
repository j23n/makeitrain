import SwiftUI
#if os(iOS)
import UIKit
#endif

// What the Mac's and the iPhone's and iPad's Settings share.

/// What this device is called in sentences, such as "Calendar on this
/// Mac".
@MainActor
public var deviceName: String {
    #if os(macOS)
    return "Mac"
    #else
    return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    #endif
}

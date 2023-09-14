/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The sample's app entry point.
*/

import ComposableArchitecture
import SwiftUI

/// A main entry point for the app.
@main struct InlinePhotosPickerDemoApp: App {

  /// A scene for the app's main window group.
  var body: some Scene {
    WindowGroup { ContentView(store: Store(initialState: Content.State(), reducer: { Content() })) }
  }
}

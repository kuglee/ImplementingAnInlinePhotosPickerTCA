/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A class that responds to Photos picker events.
*/

import ComposableArchitecture
import PhotosUI
import SwiftUI

/// A reducer that integrates a Photos picker.
struct Content: Reducer {
  struct State: Equatable {

    /// An array of items for the picker's selected photos.
    @BindingState var selection: [PhotosPickerItem]

    /// An array of image attachments for the picker's selected photos.
    var attachments: IdentifiedArrayOf<ImageAttachment.State>

    init(
      attachments: IdentifiedArrayOf<ImageAttachment.State> = [],
      selection: [PhotosPickerItem] = []
    ) {
      self.attachments = attachments
      self.selection = selection
    }
  }

  enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case imageAttachmentAction(id: ImageAttachment.State.ID, action: ImageAttachment.Action)
  }

  var body: some ReducerOf<Self> {
    BindingReducer()

    Reduce { state, action in
      switch action {
      case .binding(\.$selection):
        let newAttachments = state.selection.map { item in
          state.attachments[id: item.identifier] ?? ImageAttachment.State(item)
        }
        state.attachments = IdentifiedArray(uniqueElements: newAttachments, id: \.id)

        return .none
      case .binding: return .none
      case .imageAttachmentAction: return .none
      }
    }
    .forEach(\.attachments, action: /Action.imageAttachmentAction(id:action:)) { ImageAttachment() }
  }
}

/// A view that defines the app's user interface.
struct ContentView: View {

  /// A store that provides the Photos picker with a selection.
  let store: StoreOf<Content>

  /// A body property for the app's UI.
  var body: some View {
    NavigationStack {
      VStack {
        WithViewStore(self.store, observe: { $0 }) { viewStore in

          // Display a stub image if the Photos picker lacks a selection.
          self.imageList(viewStore: viewStore)

          // Define the app's Photos picker.
          PhotosPicker(
            selection: viewStore.$selection,
            selectionBehavior: .continuousAndOrdered,
            matching: .images,
            preferredItemEncoding: .current,
            photoLibrary: .shared()
          ) { Text("Select Photos") }

          // Configure a half-height Photos picker.
          .photosPickerStyle(.inline)

          // Disable the cancel button for an inline use case.
          .photosPickerDisabledCapabilities(.selectionActions)

          // Hide padding around all edges in the picker UI.
          .photosPickerAccessoryVisibility(.hidden, edges: .all).ignoresSafeArea()
          .frame(height: 200)
        }
      }
      .navigationTitle("Image Description").ignoresSafeArea(.keyboard)
    }
  }

  /// A view that lists selected photos and their descriptions.
  func imageList(viewStore: ViewStoreOf<Content>) -> some View {

    /// A container view for the list.
    Group {

      // Display a stub image if the Photos picker lacks a selection.
      if viewStore.attachments.isEmpty {
        Spacer()
        Image(systemName: "text.below.photo").font(.system(size: 150)).opacity(0.2)
        Spacer()
      } else {
        // Create a row for each selected photo in the picker.
        List {
          ForEachStore(
            self.store.scope(
              state: \.attachments,
              action: { .imageAttachmentAction(id: $0, action: $1) }
            )
          ) { ImageAttachmentView(store: $0) }
        }
        .listStyle(.plain)
      }
    }
  }
}

/// A reducer that manages an image that a person selects in the Photos picker.
struct ImageAttachment: Reducer {
  struct State: Equatable, Identifiable {
    /// Statuses that indicate the app's progress in loading a selected photo.
    enum Status: Equatable {
      /// A status indicating that the app has requested a photo.
      case loading

      /// A status indicating that the app has loaded a photo.
      case finished(UIImage)

      /// A status indicating that the photo has failed to load.
      case failed

      /// Determines whether the photo has failed to load.
      var isFailed: Bool {
        return switch self {
        case .failed: true
        default: false
        }
      }
    }

    /// An error that indicates why a photo has failed to load.
    enum LoadingError: Error { case contentTypeNotSupported }

    /// A reference to a selected photo in the picker.
    let pickerItem: PhotosPickerItem

    /// A load progress for the photo.
    var imageStatus: Status?

    /// A textual description for the photo.
    @BindingState var imageDescription: String = ""

    /// An identifier for the photo.
    nonisolated public var id: String { pickerItem.identifier }

    /// Creates an image attachment for the given picker item.
    init(_ pickerItem: PhotosPickerItem) { self.pickerItem = pickerItem }
  }

  enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case loaded(TaskResult<UIImage>)
    case task
  }

  var body: some ReducerOf<Self> {
    BindingReducer()

    Reduce { state, action in
      switch action {
      case .binding: return .none
      case let .loaded(.success(uiImage)):
        state.imageStatus = .finished(uiImage)

        return .none
      case let .loaded(.failure(error)):
        state.imageStatus = .failed
        print(error.localizedDescription)

        return .none
      case .task: return self.loadImage(state: &state)
      }
    }
  }

  /// Loads the photo that the picker item features.
  func loadImage(state: inout State) -> Effect<Action> {
    guard state.imageStatus == nil || state.imageStatus?.isFailed == true else { return .none }

    state.imageStatus = .loading

    return .run { [state] send in
      await send(
        .loaded(
          TaskResult {
            if let data = try await state.pickerItem.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data)
            {
              return uiImage
            } else {
              throw State.LoadingError.contentTypeNotSupported
            }
          }
        )
      )
    }
  }
}

/// A row item that displays a photo and a description.
struct ImageAttachmentView: View {

  /// An store that provides the image that a person selects in the Photos picker.
  let store: StoreOf<ImageAttachment>

  /// A container view for the row.
  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      HStack {

        // Define text that describes a selected photo.
        TextField("Image Description", text: viewStore.$imageDescription)

        // Add space after the description.
        Spacer()

        // Display the image that the text describes.
        switch viewStore.imageStatus {
        case .finished(let uiImage):
          Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fit).frame(height: 100)
        case .failed: Image(systemName: "exclamationmark.triangle.fill")
        default: ProgressView()
        }
      }
      .task {
        // Asynchronously display the photo.
        self.store.send(.task)
      }
    }
  }
}

/// A extension that handles the situation in which a picker item lacks a photo library.
extension PhotosPickerItem {
  fileprivate var identifier: String {
    guard let identifier = itemIdentifier else {
      fatalError("The photos picker lacks a photo library.")
    }

    return identifier
  }
}

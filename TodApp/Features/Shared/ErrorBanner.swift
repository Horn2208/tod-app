import SwiftUI

/// Says, for a moment, that something did not work.
///
/// With a server behind the app every write can fail, and most screens have
/// nowhere of their own to say so -- a vote or a chat message that silently
/// did not arrive looks like one that did. Keyed on `errorCount`, not on the
/// error: two network failures in a row are two things to say.
struct ErrorBanner: View {
    @Environment(AppStore.self) private var store
    @State private var message: String?
    /// The count when this banner last looked. Nil until it first has, so an
    /// error from before it appeared -- a failed sign-in, say -- is not
    /// announced again.
    @State private var seenCount: Int?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: 0)
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: 12) {
                        Text(message)
                            .font(.todBody(13, weight: .semibold))
                            .foregroundStyle(Color.todText)
                            .multilineTextAlignment(.center)
                        // Only after a connection failure: a refusal would
                        // only be refused again.
                        if store.canRetry {
                            Button("Nochmal") {
                                withAnimation(.snappy) { self.message = nil }
                                Task { await store.retryLast() }
                            }
                            .font(.todBody(13, weight: .bold))
                            .foregroundStyle(Color.todAccent)
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.todAccent2.opacity(0.6), lineWidth: 1))
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.snappy) { self.message = nil } }
                    .accessibilityHint("Tippen blendet den Hinweis aus")
                }
            }
            .task(id: store.errorCount) {
                guard let seen = seenCount else {
                    seenCount = store.errorCount
                    return
                }
                guard store.errorCount != seen, let error = store.lastError else { return }
                seenCount = store.errorCount
                let text = PostSongModel.message(for: error)
                withAnimation(.snappy) { message = text }
                AccessibilityNotification.Announcement(text).post()
                // Longer with a button in it, so there is time to reach it.
                try? await Task.sleep(for: .seconds(store.canRetry ? 7 : 4))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { message = nil }
            }
    }
}

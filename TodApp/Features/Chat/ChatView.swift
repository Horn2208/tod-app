import SwiftUI

struct ChatView: View {
    @Environment(AppStore.self) private var store
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.currentGroup?.chatMessages ?? []) { message in
                        HStack {
                            if message.isFromCurrentUser { Spacer() }
                            Text(message.text)
                                .font(.todBody(14))
                                .padding(10)
                                .background(message.isFromCurrentUser ? Color.todAccent.opacity(0.85) : Color.todSurface2)
                                .foregroundStyle(Color.todText)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            if !message.isFromCurrentUser { Spacer() }
                        }
                    }
                }
        // Claim the full width explicitly; do not rely on a child
            // (button, spacer) happening to stretch the container.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color.todBackground)

            HStack {
                TextField("Nachricht...", text: $draft)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.todSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button("Senden") {
                    let text = draft
                    draft = ""
                    Task { await store.sendMessage(text) }
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Chat")
    }
}

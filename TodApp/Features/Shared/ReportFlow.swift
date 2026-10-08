import SwiftUI

/// Something about to be reported, with what the dialogs need to name it.
struct ReportDraft: Identifiable {
    let id = UUID()
    let groupID: String
    let target: Report.Target
    /// Who wrote it, or who it is. Nil only when the app does not know.
    let personID: String?
    let personName: String
    /// "Nachricht von Lena", "Song „Nights“" -- the dialog's title.
    let what: String
    let excerpt: String?

    func report(because reason: ReportReason) -> Report {
        Report(groupID: groupID, target: target, reportedUserID: personID, reason: reason, excerpt: excerpt)
    }
}

/// Someone about to be blocked, until it is confirmed.
struct BlockDraft: Identifiable {
    let id: String
    let name: String
}

extension View {
    /// Asks why, sends the report, thanks, and offers to block the person.
    func reportFlow(_ draft: Binding<ReportDraft?>) -> some View {
        modifier(ReportFlow(draft: draft))
    }

    /// Asks before blocking, naming the person and what changes.
    func blockConfirmation(_ draft: Binding<BlockDraft?>) -> some View {
        modifier(BlockConfirmation(draft: draft))
    }
}

private struct ReportFlow: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var draft: ReportDraft?
    @State private var sent: ReportDraft?
    @State private var blocking: BlockDraft?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                draft.map { "\($0.what) melden" } ?? "",
                isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } }),
                titleVisibility: .visible,
                presenting: draft
            ) { draft in
                ForEach(ReportReason.allCases, id: \.self) { reason in
                    Button(reason.label) {
                        Task {
                            if await store.report(draft.report(because: reason)) { sent = draft }
                        }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { draft in
                Text("Was stimmt damit nicht? Die Meldung geht an uns, nicht an \(draft.personName).")
            }
            .alert(
                "Danke, ist gemeldet",
                isPresented: Binding(get: { sent != nil }, set: { if !$0 { sent = nil } }),
                presenting: sent
            ) { sent in
                if let personID = sent.personID, !store.isBlocked(personID) {
                    Button("\(sent.personName) blockieren", role: .destructive) {
                        blocking = BlockDraft(id: personID, name: sent.personName)
                    }
                }
                Button("Fertig", role: .cancel) {}
            } message: { sent in
                Text("Wir sehen es uns an. Willst du von \(sent.personName) nichts mehr sehen, kannst du blockieren.")
            }
            .blockConfirmation($blocking)
    }
}

private struct BlockConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var draft: BlockDraft?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            draft.map { "\($0.name) blockieren?" } ?? "",
            isPresented: Binding(get: { draft != nil }, set: { if !$0 { draft = nil } }),
            titleVisibility: .visible,
            presenting: draft
        ) { draft in
            Button("Blockieren", role: .destructive) {
                Task { await store.block(draft.id) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { draft in
            Text("Du siehst von \(draft.name) keine Songs, Kommentare und Nachrichten mehr, in keiner Gruppe. \(draft.name) erfährt davon nichts. Aufheben kannst du es in den Gruppeneinstellungen.")
        }
    }
}

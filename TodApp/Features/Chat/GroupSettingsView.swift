import PhotosUI
import SwiftUI

/// What a group is called, who may bring someone in, and who is in it.
/// Reached from the chat, because the chat is the group's hub. The season's
/// points live in the leaderboard alone.
struct GroupSettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var name = ""
    @State private var pickedPhoto: PhotosPickerItem?
    /// The code made on this visit. Not kept: a new visit makes a new one.
    @State private var invite: GroupInvite?
    @State private var isMakingInvite = false
    /// The member a "Entfernen" was tapped for, until it is confirmed.
    @State private var removing: Member?
    @State private var reporting: ReportDraft?
    @State private var blocking: BlockDraft?
    @State private var isConfirmingLeave = false
    @State private var isConfirmingDelete = false

    private var group: Group? { store.currentGroup }

    private var policy: InvitePolicy { group?.invitePolicy ?? .everyone }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                picture
                nameField
                invites
                members
                leaveOrDelete
            }
            .padding()
        }
        .dismissesKeyboardOnTap()
        .leavesRoomForMiniPlayer()
        .background(Color.todBackground)
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = group?.name ?? "" }
        // Saved once typing pauses, and on leaving; the store skips a name
        // that did not change and drops a blank one, so clearing the field to
        // retype keeps the old name until there is a new one.
        .task(id: name) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await store.updateGroup(name: name)
        }
        .onDisappear {
            let name = name
            Task { await store.updateGroup(name: name) }
        }
        .reportFlow($reporting)
        .blockConfirmation($blocking)
        .confirmationDialog(
            removing.map { "\($0.name) entfernen?" } ?? "",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { member in
            Button("Entfernen", role: .destructive) {
                guard let groupID = group?.id else { return }
                Task { await store.removeMember(member.id, from: groupID) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { member in
            Text("\(member.name) ist dann nicht mehr in \(group?.name ?? "der Gruppe"). Die Songs und Nachrichten bleiben. Mit einem neuen Code kann \(member.name) wieder beitreten.")
        }
        .confirmationDialog(
            "\(group?.name ?? "Gruppe") verlassen?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button(leavesLastLight ? "Verlassen und löschen" : "Verlassen", role: .destructive) {
                guard let groupID = group?.id else { return }
                // The chat under this screen sees the group go and closes
                // itself, and this screen with it.
                Task { await store.leaveGroup(groupID) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if leavesLastLight {
                Text("Außer dir ist niemand mehr in \(group?.name ?? "der Gruppe"). Wenn du gehst, wird die Gruppe mit allen Songs und Nachrichten gelöscht.")
            } else {
                Text("Du siehst \(group?.name ?? "die Gruppe") dann nicht mehr. Deine Songs und Nachrichten bleiben für die anderen. Zurück kommst du nur mit einem neuen Code.")
            }
        }
        .confirmationDialog(
            "\(group?.name ?? "Gruppe") löschen?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Endgültig löschen", role: .destructive) {
                guard let groupID = group?.id else { return }
                Task { await store.deleteGroup(groupID) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\(group?.name ?? "Die Gruppe") wird für alle gelöscht, mit allen Songs, Bewertungen und Nachrichten. Das lässt sich nicht rückgängig machen.")
        }
        .task(id: pickedPhoto) {
            guard let pickedPhoto,
                  let data = try? await pickedPhoto.loadTransferable(type: Data.self)
            else { return }
            await store.updateGroup(imageData: data)
        }
    }

    // MARK: - Picture and name

    private var picture: some View {
        // Worked out here: the picker's label runs in a Sendable closure,
        // which may not reach into the store.
        let label = group?.imageData == nil ? "Bild wählen" : "Bild ändern"
        return VStack(spacing: 10) {
            groupCircle
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text(label)
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }
        }
    }

    @ViewBuilder
    private var groupCircle: some View {
        if let group {
            GroupAvatar(group: group, size: 96)
        } else {
            Circle()
                .fill(Color.todSurface2)
                .overlay(Text("🎵").font(.system(size: 40)))
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gruppenname")
                .font(.todMono(11, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)

            TextField("Name der Gruppe", text: $name)
                .font(.todBody(16))
                .foregroundStyle(Color.todText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.todLine, lineWidth: 0.5)
                )
                .keepsKeyboardOnTap()
        }
    }

    // MARK: - Who may invite

    private var invites: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wer einladen darf")
                .font(.todBody(15, weight: .bold))
                .foregroundStyle(Color.todText)

            Picker("Wer einladen darf", selection: Binding(
                get: { policy },
                set: { new in
                    Task { await store.updateGroup(invitePolicy: new) }
                }
            )) {
                ForEach(InvitePolicy.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!store.mayChangeInvitePolicy)

            // Says why the control is dead rather than leaving a greyed-out
            // switch to be poked at.
            if !store.mayChangeInvitePolicy {
                Text("Das ändert nur, wer die Gruppe erstellt hat.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }

            if store.mayInvite {
                inviteCode
            } else {
                Text("Einladen kann hier nur, wer die Gruppe erstellt hat.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// A code to pass on. Made on request rather than on every visit: each one
    /// is a row on the server, and most visits are about the name.
    @ViewBuilder
    private var inviteCode: some View {
        if let invite {
            VStack(alignment: .leading, spacing: 8) {
                Text(InviteCode.display(invite.code))
                    .font(.todMono(20, weight: .semibold))
                    .foregroundStyle(Color.todText)
                    .textSelection(.enabled)
                    .accessibilityLabel("Einladungscode")
                    .accessibilityValue(invite.code.map(String.init).joined(separator: " "))
                Text("Gilt bis \(invite.expiresAt.formatted(date: .long, time: .omitted)). Wer ihn hat, kommt in die Gruppe.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextDim)
                ShareLink(item: InviteCode.message(groupName: group?.name ?? "", code: invite.code)) {
                    Label("Code teilen", systemImage: "square.and.arrow.up")
                        .font(.todBody(14, weight: .bold))
                        .foregroundStyle(Color.todAccent)
                }
            }
        } else {
            Button {
                isMakingInvite = true
                Task {
                    invite = await store.createInvite()
                    isMakingInvite = false
                }
            } label: {
                Label("Einladungscode erstellen", systemImage: "person.badge.plus")
                    .font(.todBody(14, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }
            .disabled(isMakingInvite)
        }
    }

    // MARK: - Who is in it

    private var members: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.map { $0.members.count == 1 ? "1 Mitglied" : "\($0.members.count) Mitglieder" } ?? "Mitglieder")
                .font(.todBody(15, weight: .bold))
                .foregroundStyle(Color.todText)

            ForEach(group?.members ?? []) { member in
                HStack(spacing: 12) {
                    AvatarBadge(member: member, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.isCurrentUser ? "Du" : member.name)
                            .font(.todBody(14))
                            .foregroundStyle(Color.todText)
                        if let note = note(on: member) {
                            Text(note)
                                .font(.todMono(10))
                                .foregroundStyle(Color.todTextFaint)
                        }
                    }
                    Spacer()
                    if !member.isCurrentUser, let group {
                        memberMenu(member, in: group)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func note(on member: Member) -> String? {
        var notes: [String] = []
        if member.id == group?.creatorID { notes.append("hat die Gruppe erstellt") }
        if store.isBlocked(member.id) { notes.append("blockiert") }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }

    /// What can be done about someone else: report, block or unblock, and
    /// for the creator, remove.
    private func memberMenu(_ member: Member, in group: Group) -> some View {
        Menu {
            Button("Melden", systemImage: "exclamationmark.bubble") {
                reporting = ReportDraft(
                    groupID: group.id, target: .member(member.id), personID: member.id,
                    personName: member.name, what: member.name, excerpt: nil)
            }
            if store.isBlocked(member.id) {
                Button("Nicht mehr blockieren", systemImage: "hand.raised.slash") {
                    Task { await store.unblock(member.id) }
                }
            } else {
                Button("Blockieren", systemImage: "hand.raised", role: .destructive) {
                    blocking = BlockDraft(id: member.id, name: member.name)
                }
            }
            if store.mayRemove(member, from: group) {
                Button("Aus der Gruppe entfernen", systemImage: "person.badge.minus", role: .destructive) {
                    removing = member
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.todTextDim)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Optionen für \(member.name)")
    }

    // MARK: - Leaving

    private var leavesLastLight: Bool {
        guard let group else { return false }
        return store.leaving(group) == .deleteGroup
    }

    private var leaveOrDelete: some View {
        VStack(spacing: 10) {
            Button { isConfirmingLeave = true } label: {
                Text("Gruppe verlassen")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todAccent2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.todSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if let group, store.mayDelete(group), !leavesLastLight {
                Button { isConfirmingDelete = true } label: {
                    Text("Gruppe löschen")
                        .font(.todBody(15, weight: .bold))
                        .foregroundStyle(Color.todAccent2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.todSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

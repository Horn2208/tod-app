import SwiftUI

/// The two ways into a group, offered wherever a group is missing: an account
/// starts with none, and without one Home has nothing to show.
enum GroupEntry: String, Identifiable {
    case create, join
    var id: String { rawValue }
}

/// What Home and Gruppen show before there is any group.
struct NoGroupsView: View {
    @Binding var entry: GroupEntry?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.todAccent)
                .accessibilityHidden(true)
            Text("Noch keine Gruppe")
                .font(.todDisplay(22))
                .foregroundStyle(Color.todText)
            Text("Starte eine mit deinen Leuten, oder tritt mit dem Code bei, den dir jemand geschickt hat.")
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button("Gruppe erstellen") { entry = .create }
                    .buttonStyle(TodPrimaryButtonStyle())
                Button("Mit Code beitreten") { entry = .join }
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todAccent)
                    .padding(.vertical, 8)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.todLine, lineWidth: 0.5))
    }
}

/// Home before the groups have arrived, or when they did not.
struct GroupsLoadingView: View {
    @Environment(AppStore.self) private var store
    @State private var isRetrying = false

    var body: some View {
        if store.groupsLoadFailed && !isRetrying {
            VStack(spacing: 12) {
                Text("Deine Gruppen konnten nicht geladen werden.")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                    .multilineTextAlignment(.center)
                Text("Prüf deine Verbindung.")
                    .font(.todBody(13))
                    .foregroundStyle(Color.todTextDim)
                Button("Nochmal versuchen") {
                    isRetrying = true
                    Task {
                        await store.refresh()
                        isRetrying = false
                    }
                }
                .buttonStyle(TodPrimaryButtonStyle())
            }
            .padding(.top, 60)
        } else {
            ProgressView().padding(.top, 60)
        }
    }
}

/// The sheet for either way in.
struct GroupEntrySheet: View {
    let entry: GroupEntry

    var body: some View {
        NavigationStack {
            switch entry {
            case .create: NewGroupView()
            case .join: JoinGroupView()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.todBackground)
    }
}

/// A name and a sign, and the group exists with you in it -- then straight
/// on to bringing people in, since a group of one has nobody to play with.
struct NewGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = NewGroupDraft.defaultIcon
    /// "Anderes …" chosen: the sign is typed rather than picked.
    @State private var isTypingIcon = false
    @State private var typedIcon = ""
    @State private var isSaving = false
    /// Set once the group exists: the sheet turns into the invite step.
    @State private var isMade = false
    @FocusState private var isNameFocused: Bool

    private var isValid: Bool { NewGroupDraft.name(name) != nil }

    var body: some View {
        if isMade {
            InviteStep { dismiss() }
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                field("Name", prompt: "Wie heißt eure Gruppe?", text: $name)
                    .focused($isNameFocused)
                iconGrid
                if let error = store.lastError {
                    Text(PostSongModel.message(for: error))
                        .font(.todBody(12))
                        .foregroundStyle(Color.todAccent2)
                }
            }
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Neue Gruppe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Erstellen") {
                    isSaving = true
                    Task {
                        store.lastError = nil
                        let sign = isTypingIcon ? typedIcon : icon
                        let made = await store.createGroup(name: name, icon: sign)
                        isSaving = false
                        if made { isMade = true }
                    }
                }
                .disabled(!isValid || isSaving)
            }
        }
        .onAppear {
            store.lastError = nil
            isNameFocused = true
        }
    }

    private var iconGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zeichen")
                .font(.todMono(11, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(NewGroupDraft.iconChoices, id: \.self) { choice in
                    let isPicked = !isTypingIcon && icon == choice
                    Button {
                        icon = choice
                        isTypingIcon = false
                    } label: {
                        Text(choice)
                            .font(.system(size: 24))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                isPicked ? Color.todAccent.opacity(0.25) : Color.todSurface2,
                                in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(isPicked ? Color.todAccent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isPicked ? .isSelected : [])
                }
            }
            Button(isTypingIcon ? "Aus der Auswahl nehmen" : "Anderes …") {
                isTypingIcon.toggle()
            }
            .font(.todBody(13, weight: .bold))
            .foregroundStyle(Color.todAccent)
            if isTypingIcon {
                field("Eigenes Zeichen", prompt: "Ein Emoji, sonst \(NewGroupDraft.defaultIcon)", text: $typedIcon)
            }
        }
    }

    private func field(_ title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.todMono(11, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)
            TextField(prompt, text: text)
                .font(.todBody(16))
                .foregroundStyle(Color.todText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.todLine, lineWidth: 0.5))
        }
    }
}

/// Right after a group is made: a code for it, made at once, and the share
/// sheet one tap away. The new group is the chosen one by now.
private struct InviteStep: View {
    @Environment(AppStore.self) private var store
    let onDone: () -> Void
    @State private var invite: GroupInvite?
    @State private var isMaking = true

    var body: some View {
        VStack(spacing: 18) {
            if let group = store.currentGroup {
                GroupAvatar(group: group, size: 72)
                Text("\(group.name) ist da")
                    .font(.todDisplay(22))
                    .foregroundStyle(Color.todText)
            }
            Text("Jetzt fehlen nur noch deine Leute. Schick ihnen den Link, damit sie direkt beitreten.")
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
            if let invite {
                Text(InviteCode.display(invite.code))
                    .font(.todMono(18, weight: .semibold))
                    .foregroundStyle(Color.todText)
                    .textSelection(.enabled)
                    .accessibilityLabel("Einladungscode")
                    .accessibilityValue(invite.code.map(String.init).joined(separator: " "))
                ShareLink(item: InviteCode.message(groupName: store.currentGroup?.name ?? "", code: invite.code)) {
                    Label("Einladung teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(TodPrimaryButtonStyle())
            } else if isMaking {
                ProgressView()
            } else {
                Text("Der Code ließ sich gerade nicht erstellen. In den Gruppeneinstellungen geht es auch später.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.todBackground)
        .navigationTitle("Leute einladen")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(invite == nil ? "Später" : "Fertig", action: onDone)
            }
        }
        .task {
            // Only if this person may invite -- in a new group, the creator
            // always may.
            if store.mayInvite { invite = await store.createInvite() }
            isMaking = false
        }
    }
}

/// The code someone sent, and you are in their group.
struct JoinGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Einladungscode")
                    .font(.todMono(11, weight: .semibold))
                    .foregroundStyle(Color.todTextFaint)
                TextField("abcd-ef01-2345-6789", text: $code)
                    .font(.todMono(18, weight: .semibold))
                    .foregroundStyle(Color.todText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.todLine, lineWidth: 0.5))
            }
            Text("Den Code bekommst du von jemandem aus der Gruppe. Er gilt sieben Tage.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)
            if let error = store.lastError {
                Text(PostSongModel.message(for: error))
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            }
            Spacer()
        }
        .padding()
        .background(Color.todBackground)
        .navigationTitle("Gruppe beitreten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Beitreten") {
                    isJoining = true
                    Task {
                        store.lastError = nil
                        let joined = await store.joinGroup(code: code)
                        isJoining = false
                        if joined { dismiss() }
                    }
                }
                .disabled(!InviteCode.isPlausible(code) || isJoining)
            }
        }
        .onAppear {
            store.lastError = nil
            isFocused = true
        }
    }
}

/// The "+" in the Gruppen tab.
struct GroupEntryMenu: ToolbarContent {
    @Binding var entry: GroupEntry?

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { entry = .create } label: {
                    Label("Gruppe erstellen", systemImage: "plus.circle")
                }
                Button { entry = .join } label: {
                    Label("Mit Code beitreten", systemImage: "person.badge.key")
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Color.todAccent)
            }
            .accessibilityLabel("Gruppe hinzufügen")
        }
    }
}

import PhotosUI
import SwiftUI

/// What a group is called, who may bring someone in, and where everyone
/// stands. Reached from the chat, because the chat is the group's hub.
struct GroupSettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var name = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var invitee = ""

    private var group: Group? { store.currentGroup }

    private var policy: InvitePolicy { group?.invitePolicy ?? .everyone }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                picture
                nameField
                invites
                season
            }
            .padding()
        }
        .dismissesKeyboardOnTap()
        .background(Color.todBackground)
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = group?.name ?? "" }
        .task { await store.loadSeasonTotals() }
        .task(id: pickedPhoto) {
            guard let pickedPhoto,
                  let data = try? await pickedPhoto.loadTransferable(type: Data.self)
            else { return }
            await store.updateGroup(name: name, imageData: data, invitePolicy: policy)
        }
    }

    // MARK: - Picture and name

    private var picture: some View {
        VStack(spacing: 10) {
            groupCircle
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text(group?.imageData == nil ? "Bild wählen" : "Bild ändern")
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }
        }
    }

    @ViewBuilder
    private var groupCircle: some View {
        if let data = group?.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.todSurface2)
                .overlay(Text(group?.icon ?? "🎵").font(.system(size: 40)))
                .frame(width: 96, height: 96)
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
                // Written straight through, and the repository drops a blank
                // one -- clearing the field to retype keeps the old name until
                // there is a new one, as on the profile.
                .onChange(of: name) { _, new in
                    Task { await store.updateGroup(name: new, imageData: nil, invitePolicy: policy) }
                }
                .keepsKeyboardOnTap()
        }
    }

    // MARK: - Who may invite

    private var invites: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mitglieder hinzufügen darf")
                .font(.todBody(15, weight: .bold))
                .foregroundStyle(Color.todText)

            Picker("Mitglieder hinzufügen darf", selection: Binding(
                get: { policy },
                set: { new in
                    Task { await store.updateGroup(name: name, imageData: nil, invitePolicy: new) }
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
                HStack(spacing: 10) {
                    TextField("Name", text: $invitee)
                        .font(.todBody(14))
                        .foregroundStyle(Color.todText)
                        .padding(10)
                        .background(Color.todSurface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button("Hinzufügen") {
                        let name = invitee
                        invitee = ""
                        Task { await store.addMember(named: name) }
                    }
                    .font(.todBody(14, weight: .bold))
                    .foregroundStyle(Color.todAccent)
                    .disabled(invitee.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                // Field and button together: adding one name after another
                // should not cost a tap back into the field each time.
                .keepsKeyboardOnTap()
            } else {
                Text("Du kannst hier niemanden hinzufügen.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - The season so far

    private var season: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Punkte insgesamt")
                .font(.todBody(15, weight: .bold))
                .foregroundStyle(Color.todText)

            if store.seasonTotals.allSatisfy({ $0.roundsPlayed == 0 }) {
                Text("Noch keine aufgedeckte Runde. Die Punkte von gestern zählen ab morgen mit.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextDim)
            }

            ForEach(store.seasonTotals) { total in
                HStack {
                    Text(total.name)
                        .font(.todBody(14))
                        .foregroundStyle(Color.todText)
                    Spacer()
                    Text(total.roundsPlayed == 1 ? "1 Runde" : "\(total.roundsPlayed) Runden")
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                    Text("\(total.points)")
                        .font(.todMono(14, weight: .semibold))
                        .foregroundStyle(Color.todAccent2)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

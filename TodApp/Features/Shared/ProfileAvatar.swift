import SwiftUI

/// The current user's own circle: their picture, or their initials until they
/// pick one. Separate from `AvatarBadge`, which draws a *member* of a group --
/// that one carries a posted-today ring and has no picture to show.
struct ProfileAvatar: View {
    let profile: UserProfile
    var size: CGFloat = 40

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.todAccent, lineWidth: size > 60 ? 2 : 1.5))
    }

    @ViewBuilder
    private var content: some View {
        if let data = profile.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.todSurface2.overlay(
                Text(initials)
                    .font(.todMono(size * 0.32, weight: .semibold))
                    .foregroundStyle(Color.todText)
            )
        }
    }

    private var initials: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "DU" : String(trimmed.prefix(2)).uppercased()
    }
}

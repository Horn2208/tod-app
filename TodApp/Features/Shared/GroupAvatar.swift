import SwiftUI

/// A group's circle: its picture when it has one, its emoji when not. The
/// groups feed, the settings and the switcher on Home all draw it, so it lives
/// here once rather than three times.
struct GroupAvatar: View {
    let group: Group
    var size: CGFloat = 52

    var body: some View {
        if let data = group.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(Color.todSurface2)
                .overlay(Text(group.icon).font(.system(size: size * 0.44)))
                .frame(width: size, height: size)
                // An emoji read out by its own name says nothing about the group;
                // whatever shows the circle names the group itself.
                .accessibilityHidden(true)
        }
    }
}

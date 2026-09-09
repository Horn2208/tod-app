import SwiftUI

/// A member's circle. Was private to TodayView until the groups feed needed the
/// same thing with a ring around it; two copies of this would have been the
/// fourth duplicated helper in this project.
struct AvatarBadge: View {
    let member: Member
    var size: CGFloat = 40
    /// The groups feed rings whoever has already posted today. TodayView shows
    /// the same people without it, so the ring is opt-in rather than implied.
    var showsPostedRing = false

    var body: some View {
        Circle()
            .fill(member.hasPostedToday ? Color.todGood.opacity(0.25) : Color.todSurface2)
            .overlay(
                Text(initials)
                    .font(.todMono(size * 0.3, weight: .semibold))
                    .foregroundStyle(Color.todText)
            )
            .overlay(ring)
            .frame(width: size, height: size)
    }

    private var initials: String {
        member.isCurrentUser ? "DU" : String(member.name.prefix(2)).uppercased()
    }

    @ViewBuilder
    private var ring: some View {
        if showsPostedRing && member.hasPostedToday {
            // Pink to gold rather than Instagram's orange-purple: the shape is
            // borrowed, the colours stay this app's own.
            Circle().strokeBorder(
                AngularGradient(
                    colors: [.todAccent, .todAccent2, .todAccent],
                    center: .center
                ),
                lineWidth: 2.5
            )
        } else if member.isCurrentUser {
            Circle().strokeBorder(Color.todAccent, lineWidth: 2)
        }
    }
}

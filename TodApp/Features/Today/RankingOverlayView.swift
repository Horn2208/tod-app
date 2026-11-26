import SwiftUI

/// Yesterday's ranking as a card over a dimmed Home (`RankingOverlay`). The
/// rows come in one after another and the points count up from zero; your
/// own points light up once they have arrived. Closed with "×", "Weiter" or
/// on the way to the comments.
struct RankingOverlayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let groupName: String
    let rows: [RankingOverlay.Row]
    let onClose: () -> Void
    let onComments: () -> Void

    /// How many rows are in so far.
    @State private var shownRows = 0
    /// Whether the points have counted up to their real value.
    @State private var isCounted = false
    /// The card's arrival: a fade and a small grow from where it will sit.
    @State private var isIn = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            card
                .padding(.horizontal, Space.xl - 4)
                .opacity(isIn ? 1 : 0)
                .scaleEffect(isIn || reduceMotion ? 1 : 0.96)
        }
        .task { await play() }
        .onAppear { withAnimation(Motion.enter) { isIn = true } }
    }

    private var card: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gestern in \(groupName)")
                    .font(.todSerif(.title2))
                    .foregroundStyle(Color.todText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.todTextDim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Schließen")
            }
            .padding(.trailing, -10)

            Text(RankingOverlay.resultLine(rows))
                .font(.todCaption)
                .foregroundStyle(Color.todTextDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: Space.xs) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        // Laid out from the start, so the card keeps its
                        // size while the rows come in.
                        rowView(row)
                            .opacity(shownRows > 0 ? 1 : 0)
                            .offset(y: shownRows > 0 ? 0 : 12)
                            .animation(Motion.enter.delay(Motion.stagger(index)), value: shownRows)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button("Kommentare ansehen", action: onComments)
                    .buttonStyle(TodPrimaryButtonStyle())
                    .accessibilityHint("Öffnet die Auflösung mit allen Bewertungen")
                Button("Weiter", action: onClose)
                    .font(.todBody(15, weight: .semibold))
                    .foregroundStyle(Color.todTextDim)
                    .frame(maxWidth: .infinity, minHeight: Space.hit)
            }
        }
        .padding(Space.xl - 4)
        .todGlassCard(radius: Radius.sheet + 4)
        .todElevated()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(RankingOverlay.spokenSummary(rows))
    }

    private func rowView(_ row: RankingOverlay.Row) -> some View {
        let shownPoints = isCounted ? row.points : 0
        return HStack(spacing: 10) {
            Text("\(row.place).")
                .font(.todMono(13, weight: .semibold))
                .foregroundStyle(row.place == 1 ? Color.todAccent2 : Color.todTextDim)
                .frame(width: 26, alignment: .leading)
            Color.clear
                .frame(width: 40, height: 40)
                .overlay { CrossfadeCover(url: row.submission.coverURL, placeholderHex: row.submission.coverColorHex) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.art))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.submission.track)
                    .font(.todBody(14, weight: .bold))
                    .foregroundStyle(Color.todText)
                    .lineLimit(1)
                Text(store.voterName(row.submission.posterID))
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if row.gems > 0 {
                Text("💎 \(row.gems)")
                    .font(.todMono(12))
                    .foregroundStyle(Color.todTextFaint)
            }
            Text("\(shownPoints)")
                .font(.todMono(16, weight: .bold))
                .foregroundStyle(row.isOwn ? Color.todAccent2 : Color.todText)
                .contentTransition(.numericText(value: Double(shownPoints)))
                .frame(minWidth: 28, alignment: .trailing)
                .todGlow(color: row.isOwn && isCounted ? .todAccent2 : .clear)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background {
            if row.isOwn {
                RoundedRectangle(cornerRadius: Radius.chip)
                    .fill(Color.todAccent2.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.todAccent2.opacity(0.5), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row))
    }

    private func spoken(_ row: RankingOverlay.Row) -> String {
        var parts = [
            "Platz \(row.place)",
            Spoken.song(track: row.submission.track, artist: row.submission.artist),
            "von \(store.voterName(row.submission.posterID))",
            RankingOverlay.points(row.points),
        ]
        if row.gems > 0 { parts.append(Spoken.gems(row.gems)) }
        return parts.joined(separator: ", ")
    }

    /// Rows one after another, then the points count up. Reduce Motion: the
    /// final values at once.
    private func play() async {
        AccessibilityNotification.Announcement(RankingOverlay.spokenSummary(rows)).post()
        guard !reduceMotion else {
            shownRows = rows.count
            isCounted = true
            return
        }
        // Peak of the day: the rows stagger in (45ms apart, 300ms in all),
        // then the points count up in under a second.
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(Motion.enter) { shownRows = rows.count }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeOut(duration: 0.7)) { isCounted = true }
    }
}

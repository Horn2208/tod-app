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

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            card
                .padding(.horizontal, 20)
        }
        .task { await play() }
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
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        // Laid out from the start, so the card keeps its
                        // size while the rows come in.
                        rowView(row)
                            .opacity(index < shownRows ? 1 : 0)
                            .offset(y: index < shownRows ? 0 : 12)
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
                    .foregroundStyle(Color.todText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(20)
        .todGlassCard(radius: 28)
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
                .frame(width: 32, height: 32)
                .overlay { CrossfadeCover(url: row.submission.coverURL, placeholderHex: row.submission.coverColorHex) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            if row.isOwn {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.todAccent2.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.todAccent2.opacity(0.5), lineWidth: 1))
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
        for index in rows.indices {
            try? await Task.sleep(for: .milliseconds(index == 0 ? 250 : 120))
            withAnimation(.snappy) { shownRows = index + 1 }
        }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.snappy(duration: 0.9)) { isCounted = true }
    }
}

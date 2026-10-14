import SwiftUI

/// The streak as a calendar: month by month back through the days you posted
/// on. Opened from the streak on Home.
struct StreakCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    let postedDates: [Date]
    let currentStreak: Int

    @State private var month = StreakCalendar.latestMonth()

    private var calendar: Calendar { StreakCalendar.calendar }
    private var earliest: Date { StreakCalendar.earliestMonth(postedDates: postedDates) }
    private var latest: Date { StreakCalendar.latestMonth() }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                monthPager
                grid
                legend
            }
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Deine Serie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(currentStreak)")
                    .font(.todDisplay(44))
            }
            .foregroundStyle(TodayView.streakSheen)
            Text(currentStreak == 1 ? "Tag in Folge" : "Tage in Folge")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
        }
        .accessibilityElement(children: .combine)
    }

    private var monthPager: some View {
        HStack {
            pageButton("chevron.left", label: "Früherer Monat", by: -1, isEnabled: month > earliest)
            Spacer()
            Text(StreakCalendar.title(ofMonthContaining: month))
                .font(.todBody(16, weight: .bold))
                .foregroundStyle(Color.todText)
            Spacer()
            pageButton("chevron.right", label: "Späterer Monat", by: 1, isEnabled: month < latest)
        }
    }

    private func pageButton(_ symbol: String, label: String, by months: Int, isEnabled: Bool) -> some View {
        Button { step(months) } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.todAccent)
                .frame(width: 44, height: 44)
        }
        .disabled(!isEnabled)
        // A custom colour does not dim by itself when the button is disabled.
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private var grid: some View {
        let weeks = StreakCalendar.weeks(ofMonthContaining: month, postedDates: postedDates)

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(StreakCalendar.weekdaySymbols(), id: \.self) { symbol in
                    Text(symbol)
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(weeks.joined().enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
        .padding(14)
        .todGlassCard(radius: 20)
    }

    private func cell(_ day: StreakCalendar.Day) -> some View {
        Text("\(day.number)")
            .font(.todMono(13, weight: day.posted ? .bold : .regular))
            .foregroundStyle(cellText(day))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                if day.posted {
                    Circle().fill(TodayView.streakSheen).frame(width: 34, height: 34)
                }
            }
            .overlay {
                if day.isToday {
                    Circle().strokeBorder(Color.todAccent, lineWidth: 1.5).frame(width: 37, height: 37)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(day))
    }

    private func cellText(_ day: StreakCalendar.Day) -> Color {
        if day.posted { return .todBackground }
        return day.isFuture ? Color.todTextFaint.opacity(0.5) : .todTextDim
    }

    private func spoken(_ day: StreakCalendar.Day) -> String {
        let date = day.date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE")))
        if day.isFuture { return date }
        return day.posted ? "\(date), gepostet" : "\(date), nicht gepostet"
    }

    private var legend: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Circle().fill(TodayView.streakSheen).frame(width: 12, height: 12)
                Text("Gepostet")
            }
            HStack(spacing: 6) {
                Circle().strokeBorder(Color.todAccent, lineWidth: 1.5).frame(width: 12, height: 12)
                Text("Heute")
            }
        }
        .font(.todBody(12))
        .foregroundStyle(Color.todTextFaint)
        .accessibilityHidden(true)
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = min(max(next, earliest), latest)
    }
}

import Foundation

/// How old a comment reads under it.
///
/// Two things this gets right that the obvious one-liner does not:
///
/// A comment written a moment ago came back from `.relative` as "in 0
/// Sekunden" -- the rounding lands on the wrong side of now, and something
/// just posted must not appear to arrive from the future. A clock a few
/// seconds out of step points the same wording forwards, so the guard covers
/// both directions.
///
/// And `Date.RelativeFormatStyle` always measures against the real clock: a
/// `now` handed to it is ignored, which makes the rule untestable at any age
/// past a minute. `RelativeDateTimeFormatter` takes the reference date, so
/// this one can be checked.
enum CommentTime {
    /// Anything younger than a minute is simply "gerade eben" -- the exact
    /// number of seconds is noise at that age, and it is the range where the
    /// relative wording breaks.
    static func label(for postedAt: Date, now: Date = Date(), locale: Locale = .current) -> String {
        guard now.timeIntervalSince(postedAt) >= 60 else { return "gerade eben" }
        // Built per call rather than shared: this type is not thread-safe, and
        // a comment list is short enough that one formatter per row costs
        // nothing worth the risk of a shared one.
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: postedAt, relativeTo: now)
    }
}

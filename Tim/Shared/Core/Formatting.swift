import Foundation

extension TimeInterval {
    /// "1h 42m" / "8m" — used in the status screen and the session summaries.
    var timDurationText: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}

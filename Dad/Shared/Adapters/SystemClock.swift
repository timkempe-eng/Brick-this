import Foundation

struct SystemClock: Clock {
    var now: Date { Date() }
}

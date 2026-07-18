import Foundation
import PhotonzCore
import Testing

@Suite("RelativeTime")
struct RelativeTimeTests {
    @Test func justNowUnderFiveSeconds() {
        #expect(RelativeTime.string(secondsAgo: 0) == "just now")
        #expect(RelativeTime.string(secondsAgo: 4) == "just now")
    }

    @Test func negativeElapsedClampsToJustNow() {
        // Clock skew / a capture stamped slightly in the future shouldn't read
        // as a giant "ago" number.
        #expect(RelativeTime.string(secondsAgo: -30) == "just now")
    }

    @Test func seconds() {
        #expect(RelativeTime.string(secondsAgo: 15) == "15 seconds ago")
        #expect(RelativeTime.string(secondsAgo: 59) == "59 seconds ago")
    }

    @Test func minutesSingularAndPlural() {
        #expect(RelativeTime.string(secondsAgo: 60) == "1 minute ago")
        #expect(RelativeTime.string(secondsAgo: 90) == "1 minute ago")
        #expect(RelativeTime.string(secondsAgo: 30 * 60) == "30 minutes ago")
        #expect(RelativeTime.string(secondsAgo: 59 * 60) == "59 minutes ago")
    }

    @Test func hoursSingularAndPlural() {
        #expect(RelativeTime.string(secondsAgo: 60 * 60) == "1 hour ago")
        #expect(RelativeTime.string(secondsAgo: 2 * 3600) == "2 hours ago")
        #expect(RelativeTime.string(secondsAgo: 23 * 3600) == "23 hours ago")
    }

    @Test func yesterdayAndDays() {
        #expect(RelativeTime.string(secondsAgo: 24 * 3600) == "yesterday")
        #expect(RelativeTime.string(secondsAgo: 47 * 3600) == "yesterday")
        #expect(RelativeTime.string(secondsAgo: 2 * 86400) == "2 days ago")
        #expect(RelativeTime.string(secondsAgo: 6 * 86400) == "6 days ago")
    }

    @Test func weeksAndMonthsAndYears() {
        #expect(RelativeTime.string(secondsAgo: 7 * 86400) == "1 week ago")
        #expect(RelativeTime.string(secondsAgo: 21 * 86400) == "3 weeks ago")
        #expect(RelativeTime.string(secondsAgo: 40 * 86400) == "1 month ago")
        #expect(RelativeTime.string(secondsAgo: 200 * 86400) == "6 months ago")
        #expect(RelativeTime.string(secondsAgo: 400 * 86400) == "1 year ago")
        #expect(RelativeTime.string(secondsAgo: 800 * 86400) == "2 years ago")
    }

    @Test func dateOverloadUsesElapsed() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let then = Date(timeIntervalSinceReferenceDate: 10_000 - 120)
        #expect(RelativeTime.string(from: then, to: now) == "2 minutes ago")
    }

    @Test func noEmDashesEver() {
        // Sample a spread of buckets; user copy rule forbids em dashes.
        for s in [0.0, 30, 600, 7200, 90_000, 600_000, 3_000_000, 40_000_000] {
            #expect(!RelativeTime.string(secondsAgo: s).contains("\u{2014}"))
        }
    }
}

// Standalone tests never load the app, access HID, or write real preferences.
import XCTest

@main
struct SnapshotStorageTests {
    static func main() {
        let suite = MouseSnapshotStoreTests.defaultTestSuite
        suite.run()
        guard let result = suite.testRun, result.executionCount == 7, result.hasSucceeded else { exit(1) }
    }
}

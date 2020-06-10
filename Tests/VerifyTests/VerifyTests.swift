import XCTest
@testable import Verify

final class VerifyTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Verify().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

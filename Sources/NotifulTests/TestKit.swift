import Foundation

/// Minimal dependency-free assertion harness (XCTest needs full Xcode; we only have CLT).
final class TestKit {
    private(set) var passed = 0
    private(set) var failed = 0
    private var current = ""

    func test(_ name: String, _ body: () -> Void) {
        current = name
        body()
    }

    func assert(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if condition {
            passed += 1
        } else {
            failed += 1
            print("  ✗ [\(current)] \(message)  (\(file):\(line))")
        }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assert(a == b, "\(message) — expected \(b), got \(a)", file: file, line: line)
    }

    func nilCheck<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assert(value == nil, "\(message) — expected nil, got \(String(describing: value))", file: file, line: line)
    }

    func notNil<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assert(value != nil, "\(message) — expected non-nil", file: file, line: line)
    }

    func summary() -> Int {
        print("\n\(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}

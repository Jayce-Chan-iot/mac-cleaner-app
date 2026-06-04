import XCTest
@testable import MacCleanerApp

final class JunkDetectorTests: XCTestCase {
    let junkDetector = JunkDetector()
    let home = FileManager.default.homeDirectoryForCurrentUser

    // J01: User cache should match the cache rule
    func test_cacheRule_matchesUserCache() {
        let cacheURL = home.appendingPathComponent("Library/Caches/com.apple.Safari/Cache.db")
        let cacheBase = home.appendingPathComponent("Library/Caches")
        let matches = junkDetector.matchesRule(url: cacheURL, baseURL: cacheBase, pattern: nil)
        XCTAssertTrue(matches, "User cache should match cache rule")
    }

    // J02: Log files should match the log rule
    func test_logRule_matchesSystemLog() {
        let logURL = home.appendingPathComponent("Library/Logs/DiagnosticReports/SpinReport.spin")
        let logBase = home.appendingPathComponent("Library/Logs")
        let matches = junkDetector.matchesRule(url: logURL, baseURL: logBase, pattern: nil)
        XCTAssertTrue(matches, "Log files should match log rule")
    }

    // J03: Xcode DerivedData should match xcodeJunk rule
    func test_xcodeRule_matchesDerivedData() {
        let xcodeURL = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/ModuleCache/foo.o")
        let xcodeBase = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let matches = junkDetector.matchesRule(url: xcodeURL, baseURL: xcodeBase, pattern: nil)
        XCTAssertTrue(matches, "Xcode DerivedData should match xcodeJunk rule")
    }

    // J04: User Documents must NOT be matched as junk
    func test_userDocument_NOT_matchedAsJunk() {
        let docURL = home.appendingPathComponent("Documents/work/presentation.key")
        let rules = junkDetector.rules
        var matched = false
        for (_, baseURL, pattern) in rules {
            if junkDetector.matchesRule(url: docURL, baseURL: baseURL, pattern: pattern) {
                matched = true
                break
            }
        }
        XCTAssertFalse(matched, "~/Documents files must NOT match any junk rule")
    }

    // J05: User Desktop must NOT be matched as junk
    func test_userDesktop_NOT_matchedAsJunk() {
        let desktopURL = home.appendingPathComponent("Desktop/tax-2025.pdf")
        let rules = junkDetector.rules
        var matched = false
        for (_, baseURL, pattern) in rules {
            if junkDetector.matchesRule(url: desktopURL, baseURL: baseURL, pattern: pattern) {
                matched = true
                break
            }
        }
        XCTAssertFalse(matched, "~/Desktop files must NOT match any junk rule")
    }

    // J06: WeChat data must NOT be matched as junk
    func test_weChatData_NOT_matchedAsJunk() {
        let wechatURL = home.appendingPathComponent("Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat")
        let rules = junkDetector.rules
        var matched = false
        for (_, baseURL, pattern) in rules {
            if junkDetector.matchesRule(url: wechatURL, baseURL: baseURL, pattern: pattern) {
                matched = true
                break
            }
        }
        XCTAssertFalse(matched, "WeChat data must NOT match any junk rule")
    }

    // J07: Chrome profile must NOT be matched as junk
    func test_chromeProfile_NOT_matchedAsJunk() {
        let chromeURL = home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/History")
        let rules = junkDetector.rules
        var matched = false
        for (_, baseURL, pattern) in rules {
            if junkDetector.matchesRule(url: chromeURL, baseURL: baseURL, pattern: pattern) {
                matched = true
                break
            }
        }
        XCTAssertFalse(matched, "Chrome profile must NOT match any junk rule")
    }

    // J08: Rule count must be exactly 22
    func test_ruleCount_equals22() {
        XCTAssertEqual(junkDetector.rules.count, 22, "JunkDetector must have exactly 22 rules")
    }

    // J09: Docker container should match dockerLeftovers
    func test_dockerContainer_matchesRule() {
        let dockerURL = home.appendingPathComponent("Library/Containers/com.docker.docker/somefile")
        let dockerBase = home.appendingPathComponent("Library/Containers/com.docker.docker")
        let matches = junkDetector.matchesRule(url: dockerURL, baseURL: dockerBase, pattern: nil)
        XCTAssertTrue(matches, "Docker container should match dockerLeftovers rule")
    }

    // J10: VS Code user settings must NOT be matched
    func test_vscodeSettings_NOT_matchedAsJunk() {
        let vscodeURL = home.appendingPathComponent("Library/Application Support/Code/User/settings.json")
        let rules = junkDetector.rules
        var matched = false
        for (_, baseURL, pattern) in rules {
            if junkDetector.matchesRule(url: vscodeURL, baseURL: baseURL, pattern: pattern) {
                matched = true
                break
            }
        }
        XCTAssertFalse(matched, "VS Code settings must NOT match any junk rule")
    }
}

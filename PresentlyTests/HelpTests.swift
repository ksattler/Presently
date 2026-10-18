import XCTest
@testable import Presently

final class HelpTests: XCTestCase {
    func testEveryTopicHasTitleAndText() {
        for topic in HelpTopic.allCases {
            XCTAssertFalse(topic.title.isEmpty, "\(topic)")
            XCTAssertFalse(topic.paragraphs.isEmpty, "\(topic)")
            XCTAssertFalse(NSImage(systemSymbolName: topic.symbol, accessibilityDescription: nil) == nil, "\(topic.symbol)")
        }
        XCTAssertEqual(Set(HelpTopic.allCases.map(\.title)).count, HelpTopic.allCases.count)
    }

    func testParagraphsAreValidMarkdown() throws {
        for topic in HelpTopic.allCases {
            for p in topic.paragraphs {
                let text = try AttributedString(markdown: p, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                // Emphasis markers are consumed, not shown literally.
                XCTAssertFalse(String(text.characters).contains("**"), p)
            }
        }
    }

    func testKeysTopicListsTheAboutPanelShortcuts() {
        XCTAssertEqual(HelpTopic.keys.shortcuts.map(\.keys), AboutPanel.shortcuts.map(\.keys))
        XCTAssertTrue(HelpTopic.presenting.shortcuts.isEmpty)
    }

    func testSearch() {
        XCTAssertEqual(HelpTopic.allCases.filter { $0.matches("") }, HelpTopic.allCases)
        XCTAssertEqual(HelpTopic.allCases.filter { $0.matches("  ") }, HelpTopic.allCases)
        XCTAssertTrue(HelpTopic.notes.matches("PDFPC"))
        XCTAssertTrue(HelpTopic.notes.matches(HelpTopic.notes.title.lowercased()))
        // Key rows are searched too.
        XCTAssertTrue(HelpTopic.keys.matches(String(localized: "Freeze audience view")))
        XCTAssertTrue(HelpTopic.allCases.allSatisfy { !$0.matches("xyzzy") })
    }
}

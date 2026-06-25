import XCTest
@testable import DesktopTodo

final class OpenAIServiceTests: XCTestCase {

    // MARK: - parseSSELine

    func testParseSSELine_validDelta() {
        let line = #"data: {"id":"c1","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}]}"#
        XCTAssertEqual(OpenAIService.parseSSELine(line), "Hello")
    }

    func testParseSSELine_done() {
        XCTAssertNil(OpenAIService.parseSSELine("data: [DONE]"))
    }

    func testParseSSELine_emptyDelta() {
        let line = #"data: {"id":"c1","choices":[{"delta":{},"index":0,"finish_reason":"stop"}]}"#
        XCTAssertNil(OpenAIService.parseSSELine(line))
    }

    func testParseSSELine_emptyLine() {
        XCTAssertNil(OpenAIService.parseSSELine(""))
    }

    func testParseSSELine_commentLine() {
        XCTAssertNil(OpenAIService.parseSSELine(": ping"))
    }

    // MARK: - extractLines

    func testExtractLines_singleComplete() {
        let (lines, remaining) = OpenAIService.extractLines(buffer: "", appending: "准备汇报\n")
        XCTAssertEqual(lines, ["准备汇报"])
        XCTAssertEqual(remaining, "")
    }

    func testExtractLines_multipleLines() {
        let (lines, remaining) = OpenAIService.extractLines(
            buffer: "准备汇报\n收集数",
            appending: "据\n制作PPT"
        )
        XCTAssertEqual(lines, ["准备汇报", "收集数据"])
        XCTAssertEqual(remaining, "制作PPT")
    }

    func testExtractLines_noNewline() {
        let (lines, remaining) = OpenAIService.extractLines(buffer: "准备", appending: "汇报")
        XCTAssertEqual(lines, [])
        XCTAssertEqual(remaining, "准备汇报")
    }

    func testExtractLines_emptyLinesSkipped() {
        let (lines, _) = OpenAIService.extractLines(buffer: "", appending: "\n第一步\n\n第二步\n")
        XCTAssertEqual(lines, ["第一步", "第二步"])
    }

    func testExtractLines_trailingBufferPreserved() {
        let (lines, remaining) = OpenAIService.extractLines(buffer: "", appending: "第一步\n第二步")
        XCTAssertEqual(lines, ["第一步"])
        XCTAssertEqual(remaining, "第二步")
    }
}

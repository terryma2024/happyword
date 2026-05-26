import XCTest
@testable import WordMagicGame

final class MessageBubbleGeometryTests: XCTestCase {
    func testBossStyleDefaultTailMatchesHarmonyCoordinates() {
        let tail = MessageBubbleTail.preset(
            .bottomRight,
            box: MessageBubbleBox.bossStyle
        )

        XCTAssertEqual(tail.baseStart, MessageBubblePoint(x: 172, y: 96))
        XCTAssertEqual(tail.baseEnd, MessageBubblePoint(x: 196, y: 96))
        XCTAssertEqual(tail.tip, MessageBubblePoint(x: 212, y: 112))
    }

    func testAllPresetsAreAvailableInHarmonyOrder() {
        XCTAssertEqual(MessageBubbleTailPreset.allCases, [
            .topLeft,
            .topMiddle,
            .topRight,
            .bottomLeft,
            .bottomMiddle,
            .bottomRight,
            .leftTop,
            .leftMiddle,
            .leftBottom,
            .rightTop,
            .rightMiddle,
            .rightBottom,
        ])
    }

    func testPresetTailCoordinatesMatchEachSide() {
        let box = MessageBubbleBox(
            width: 120,
            height: 80,
            borderWidth: 1,
            tailBase: 20,
            tailLength: 14,
            inset: 10,
            tipInset: 6
        )

        XCTAssertEqual(MessageBubbleTail.preset(.topLeft, box: box).tip, MessageBubblePoint(x: 6, y: -14))
        XCTAssertEqual(MessageBubbleTail.preset(.topMiddle, box: box).tip, MessageBubblePoint(x: 60, y: -14))
        XCTAssertEqual(MessageBubbleTail.preset(.topRight, box: box).tip, MessageBubblePoint(x: 114, y: -14))
        XCTAssertEqual(MessageBubbleTail.preset(.bottomLeft, box: box).tip, MessageBubblePoint(x: 6, y: 94))
        XCTAssertEqual(MessageBubbleTail.preset(.bottomMiddle, box: box).tip, MessageBubblePoint(x: 60, y: 94))
        XCTAssertEqual(MessageBubbleTail.preset(.bottomRight, box: box).tip, MessageBubblePoint(x: 114, y: 94))
        XCTAssertEqual(MessageBubbleTail.preset(.leftTop, box: box).tip, MessageBubblePoint(x: -14, y: 6))
        XCTAssertEqual(MessageBubbleTail.preset(.leftMiddle, box: box).tip, MessageBubblePoint(x: -14, y: 40))
        XCTAssertEqual(MessageBubbleTail.preset(.leftBottom, box: box).tip, MessageBubblePoint(x: -14, y: 74))
        XCTAssertEqual(MessageBubbleTail.preset(.rightTop, box: box).tip, MessageBubblePoint(x: 134, y: 6))
        XCTAssertEqual(MessageBubbleTail.preset(.rightMiddle, box: box).tip, MessageBubblePoint(x: 134, y: 40))
        XCTAssertEqual(MessageBubbleTail.preset(.rightBottom, box: box).tip, MessageBubblePoint(x: 134, y: 74))
    }

    func testFrameExpandsForTailOutsideBubbleBounds() {
        let frame = MessageBubbleFrame.bubbleFrame(
            width: 224,
            height: 96,
            tail: MessageBubbleTail.bossStyleDefault
        )

        XCTAssertEqual(frame.width, 224)
        XCTAssertEqual(frame.height, 112)
        XCTAssertEqual(frame.offsetX, 0)
        XCTAssertEqual(frame.offsetY, 0)
    }
}

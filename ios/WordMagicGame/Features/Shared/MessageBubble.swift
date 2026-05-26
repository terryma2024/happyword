import SwiftUI

struct MessageBubblePoint: Equatable, Hashable {
    var x: CGFloat
    var y: CGFloat
}

struct MessageBubbleTail: Equatable, Hashable {
    var baseStart: MessageBubblePoint
    var baseEnd: MessageBubblePoint
    var tip: MessageBubblePoint

    static let bossStyleDefault = MessageBubbleTail.preset(.bottomRight, box: .bossStyle)

    static func preset(_ preset: MessageBubbleTailPreset, box: MessageBubbleBox) -> MessageBubbleTail {
        if preset.isTop {
            let startX = horizontalBaseStart(preset: preset, box: box)
            return MessageBubbleTail(
                baseStart: MessageBubblePoint(x: startX, y: 0),
                baseEnd: MessageBubblePoint(x: startX + box.tailBase, y: 0),
                tip: MessageBubblePoint(x: horizontalTipX(preset: preset, box: box, baseStart: startX), y: -box.tailLength)
            )
        }
        if preset.isBottom {
            let startX = horizontalBaseStart(preset: preset, box: box)
            return MessageBubbleTail(
                baseStart: MessageBubblePoint(x: startX, y: box.height),
                baseEnd: MessageBubblePoint(x: startX + box.tailBase, y: box.height),
                tip: MessageBubblePoint(x: horizontalTipX(preset: preset, box: box, baseStart: startX), y: box.height + box.tailLength)
            )
        }
        if preset.isLeft {
            let startY = verticalBaseStart(preset: preset, box: box)
            return MessageBubbleTail(
                baseStart: MessageBubblePoint(x: 0, y: startY),
                baseEnd: MessageBubblePoint(x: 0, y: startY + box.tailBase),
                tip: MessageBubblePoint(x: -box.tailLength, y: verticalTipY(preset: preset, box: box, baseStart: startY))
            )
        }
        let startY = verticalBaseStart(preset: preset, box: box)
        return MessageBubbleTail(
            baseStart: MessageBubblePoint(x: box.width, y: startY),
            baseEnd: MessageBubblePoint(x: box.width, y: startY + box.tailBase),
            tip: MessageBubblePoint(x: box.width + box.tailLength, y: verticalTipY(preset: preset, box: box, baseStart: startY))
        )
    }

    private static func horizontalBaseStart(preset: MessageBubbleTailPreset, box: MessageBubbleBox) -> CGFloat {
        switch preset {
        case .topLeft, .bottomLeft:
            return clampStart(box.inset, length: box.width, base: box.tailBase)
        case .topRight, .bottomRight:
            return clampStart(box.width - box.inset - box.tailBase, length: box.width, base: box.tailBase)
        default:
            return clampStart((box.width - box.tailBase) / 2, length: box.width, base: box.tailBase)
        }
    }

    private static func verticalBaseStart(preset: MessageBubbleTailPreset, box: MessageBubbleBox) -> CGFloat {
        switch preset {
        case .leftTop, .rightTop:
            return clampStart(box.inset, length: box.height, base: box.tailBase)
        case .leftBottom, .rightBottom:
            return clampStart(box.height - box.inset - box.tailBase, length: box.height, base: box.tailBase)
        default:
            return clampStart((box.height - box.tailBase) / 2, length: box.height, base: box.tailBase)
        }
    }

    private static func horizontalTipX(preset: MessageBubbleTailPreset, box: MessageBubbleBox, baseStart: CGFloat) -> CGFloat {
        let tipInset = box.tipInset ?? 0
        switch preset {
        case .topLeft, .bottomLeft:
            return tipInset
        case .topRight, .bottomRight:
            return box.width - tipInset
        default:
            return baseStart + box.tailBase / 2
        }
    }

    private static func verticalTipY(preset: MessageBubbleTailPreset, box: MessageBubbleBox, baseStart: CGFloat) -> CGFloat {
        let tipInset = box.tipInset ?? 0
        switch preset {
        case .leftTop, .rightTop:
            return tipInset
        case .leftBottom, .rightBottom:
            return box.height - tipInset
        default:
            return baseStart + box.tailBase / 2
        }
    }

    private static func clampStart(_ start: CGFloat, length: CGFloat, base: CGFloat) -> CGFloat {
        min(max(start, 0), length - base)
    }
}

enum MessageBubbleTailPreset: String, CaseIterable, Identifiable {
    case topLeft = "TopLeft"
    case topMiddle = "TopMiddle"
    case topRight = "TopRight"
    case bottomLeft = "BottomLeft"
    case bottomMiddle = "BottomMiddle"
    case bottomRight = "BottomRight"
    case leftTop = "LeftTop"
    case leftMiddle = "LeftMiddle"
    case leftBottom = "LeftBottom"
    case rightTop = "RightTop"
    case rightMiddle = "RightMiddle"
    case rightBottom = "RightBottom"

    var id: String { rawValue }

    var isTop: Bool { self == .topLeft || self == .topMiddle || self == .topRight }
    var isBottom: Bool { self == .bottomLeft || self == .bottomMiddle || self == .bottomRight }
    var isLeft: Bool { self == .leftTop || self == .leftMiddle || self == .leftBottom }
}

struct MessageBubbleBox: Equatable {
    var width: CGFloat
    var height: CGFloat
    var borderWidth: CGFloat
    var tailBase: CGFloat
    var tailLength: CGFloat
    var inset: CGFloat
    var tipInset: CGFloat?

    static let bossStyle = MessageBubbleBox(
        width: 224,
        height: 96,
        borderWidth: 1,
        tailBase: 24,
        tailLength: 16,
        inset: 28,
        tipInset: 12
    )
}

struct MessageBubbleFrame: Equatable {
    var width: CGFloat
    var height: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat

    static func bubbleFrame(width: CGFloat, height: CGFloat, tail: MessageBubbleTail?) -> MessageBubbleFrame {
        guard let tail else {
            return MessageBubbleFrame(width: width, height: height, offsetX: 0, offsetY: 0)
        }
        let minX = min(0, tail.baseStart.x, tail.baseEnd.x, tail.tip.x)
        let minY = min(0, tail.baseStart.y, tail.baseEnd.y, tail.tip.y)
        let maxX = max(width, tail.baseStart.x, tail.baseEnd.x, tail.tip.x)
        let maxY = max(height, tail.baseStart.y, tail.baseEnd.y, tail.tip.y)
        return MessageBubbleFrame(width: maxX - minX, height: maxY - minY, offsetX: -minX, offsetY: -minY)
    }
}

struct MessageBubblePadding: Equatable {
    var left: CGFloat
    var right: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    static let bossStyle = MessageBubblePadding(left: 10, right: 10, top: 10, bottom: 10)
}

struct MessageBubbleShadow: Equatable {
    var radius: CGFloat
    var color: Color
    var offsetX: CGFloat
    var offsetY: CGFloat

    static let bossStyle = MessageBubbleShadow(
        radius: 12,
        color: .black.opacity(0.14),
        offsetX: 0,
        offsetY: 4
    )

    var padding: CGSize {
        guard radius > 0 else { return .zero }
        return CGSize(width: abs(offsetX) + radius, height: abs(offsetY) + radius)
    }
}

struct MessageBubble<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var borderWidth: CGFloat
    var fill: Color
    var stroke: Color
    var contentPadding: MessageBubblePadding
    var tail: MessageBubbleTail?
    var bubbleShadow: MessageBubbleShadow
    @ViewBuilder var content: () -> Content

    init(
        width: CGFloat = MessageBubbleBox.bossStyle.width,
        height: CGFloat = MessageBubbleBox.bossStyle.height,
        radius: CGFloat = 18,
        borderWidth: CGFloat = MessageBubbleBox.bossStyle.borderWidth,
        fill: Color = MessageBubbleColor.bossFill,
        stroke: Color = MessageBubbleColor.bossStroke,
        contentPadding: MessageBubblePadding = .bossStyle,
        tail: MessageBubbleTail? = .bossStyleDefault,
        bubbleShadow: MessageBubbleShadow = .bossStyle,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.height = height
        self.radius = radius
        self.borderWidth = borderWidth
        self.fill = fill
        self.stroke = stroke
        self.contentPadding = contentPadding
        self.tail = tail
        self.bubbleShadow = bubbleShadow
        self.content = content
    }

    var body: some View {
        let frame = MessageBubbleFrame.bubbleFrame(width: width, height: height, tail: tail)
        let shadowPadding = bubbleShadow.padding
        let shape = MessageBubbleShape(width: width, height: height, radius: radius, tail: tail)

        ZStack(alignment: .topLeading) {
            shape
                .fill(fill)
                .frame(width: frame.width, height: frame.height)
                .shadow(
                    color: bubbleShadow.color,
                    radius: bubbleShadow.radius,
                    x: bubbleShadow.offsetX,
                    y: bubbleShadow.offsetY
                )
                .offset(x: shadowPadding.width, y: shadowPadding.height)

            shape
                .stroke(stroke, lineWidth: borderWidth)
                .frame(width: frame.width, height: frame.height)
                .offset(x: shadowPadding.width, y: shadowPadding.height)

            content()
                .padding(.leading, contentPadding.left)
                .padding(.trailing, contentPadding.right)
                .padding(.top, contentPadding.top)
                .padding(.bottom, contentPadding.bottom)
                .frame(width: width, height: height, alignment: .topLeading)
                .offset(x: shadowPadding.width + frame.offsetX, y: shadowPadding.height + frame.offsetY)
        }
        .frame(width: frame.width + shadowPadding.width * 2, height: frame.height + shadowPadding.height * 2)
    }
}

enum MessageBubbleColor {
    static let bossFill = Color(red: 1.0, green: 0.992, blue: 0.965)
    static let bossStroke = Color(red: 0.906, green: 0.843, blue: 0.714)
}

private enum MessageBubbleTailSide {
    case top
    case right
    case bottom
    case left
}

private struct MessageBubbleShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    var tail: MessageBubbleTail?

    func path(in rect: CGRect) -> Path {
        let safeRadius = min(radius, width / 2, height / 2)
        let frame = MessageBubbleFrame.bubbleFrame(width: width, height: height, tail: tail)
        let x = frame.offsetX
        let y = frame.offsetY
        let side = tail.map { detectTailSide(width: width, height: height, tail: $0) }
        let shiftedTail = tail.map { shifted($0, by: frame) }
        var path = Path()

        path.move(to: CGPoint(x: x + safeRadius, y: y))
        if side == .top, let shiftedTail {
            path.addLine(to: shiftedTail.baseStart.cgPoint)
            path.addLine(to: shiftedTail.tip.cgPoint)
            path.addLine(to: shiftedTail.baseEnd.cgPoint)
        }
        path.addLine(to: CGPoint(x: x + width - safeRadius, y: y))
        path.addQuadCurve(
            to: CGPoint(x: x + width, y: y + safeRadius),
            control: CGPoint(x: x + width, y: y)
        )

        if side == .right, let shiftedTail {
            path.addLine(to: shiftedTail.baseStart.cgPoint)
            path.addLine(to: shiftedTail.tip.cgPoint)
            path.addLine(to: shiftedTail.baseEnd.cgPoint)
        }
        path.addLine(to: CGPoint(x: x + width, y: y + height - safeRadius))
        path.addQuadCurve(
            to: CGPoint(x: x + width - safeRadius, y: y + height),
            control: CGPoint(x: x + width, y: y + height)
        )

        if side == .bottom, let shiftedTail {
            path.addLine(to: shiftedTail.baseEnd.cgPoint)
            path.addLine(to: shiftedTail.tip.cgPoint)
            path.addLine(to: shiftedTail.baseStart.cgPoint)
        }
        path.addLine(to: CGPoint(x: x + safeRadius, y: y + height))
        path.addQuadCurve(
            to: CGPoint(x: x, y: y + height - safeRadius),
            control: CGPoint(x: x, y: y + height)
        )

        if side == .left, let shiftedTail {
            path.addLine(to: shiftedTail.baseEnd.cgPoint)
            path.addLine(to: shiftedTail.tip.cgPoint)
            path.addLine(to: shiftedTail.baseStart.cgPoint)
        }
        path.addLine(to: CGPoint(x: x, y: y + safeRadius))
        path.addQuadCurve(
            to: CGPoint(x: x + safeRadius, y: y),
            control: CGPoint(x: x, y: y)
        )
        path.closeSubpath()
        return path
    }

    private func detectTailSide(width: CGFloat, height: CGFloat, tail: MessageBubbleTail) -> MessageBubbleTailSide {
        if tail.baseStart.y.isNearly(0), tail.baseEnd.y.isNearly(0) {
            return .top
        }
        if tail.baseStart.x.isNearly(width), tail.baseEnd.x.isNearly(width) {
            return .right
        }
        if tail.baseStart.y.isNearly(height), tail.baseEnd.y.isNearly(height) {
            return .bottom
        }
        if tail.baseStart.x.isNearly(0), tail.baseEnd.x.isNearly(0) {
            return .left
        }
        return .bottom
    }

    private func shifted(_ tail: MessageBubbleTail, by frame: MessageBubbleFrame) -> MessageBubbleTail {
        MessageBubbleTail(
            baseStart: tail.baseStart.shifted(x: frame.offsetX, y: frame.offsetY),
            baseEnd: tail.baseEnd.shifted(x: frame.offsetX, y: frame.offsetY),
            tip: tail.tip.shifted(x: frame.offsetX, y: frame.offsetY)
        )
    }
}

private extension MessageBubblePoint {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    func shifted(x dx: CGFloat, y dy: CGFloat) -> MessageBubblePoint {
        MessageBubblePoint(x: x + dx, y: y + dy)
    }
}

private extension CGFloat {
    func isNearly(_ other: CGFloat) -> Bool {
        abs(self - other) < 0.5
    }
}

import SwiftUI

struct MessageBubbleLabView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var state = MessageBubbleLabState()

    private let presetColumns = [
        GridItem(.adaptive(minimum: 112), spacing: 8),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                demoSection
                liveOutputSection
                presetsSection
                boxControls
                visualControls
                coordinateControls
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.vertical, 16)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.white)
        .accessibilityIdentifier("MessageBubbleLabPage")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.route = .devMenu
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("MessageBubbleLabBackButton")

            VStack(alignment: .leading, spacing: 2) {
                Text("Message Bubble Lab")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Debug only")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var demoSection: some View {
        labSection("Demo") {
            ZStack {
                Color(red: 0.97, green: 0.98, blue: 1.0)
                MessageBubble(
                    width: state.width,
                    height: state.height,
                    radius: state.radius,
                    borderWidth: state.borderWidth,
                    fill: state.fillColor.color,
                    stroke: state.strokeColor.color,
                    contentPadding: MessageBubblePadding(
                        left: state.paddingX,
                        right: state.paddingX,
                        top: state.paddingY,
                        bottom: state.paddingY
                    ),
                    tail: state.tail,
                    bubbleShadow: state.shadow
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Boss style bubble")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Tail follows local point coordinates.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.36, green: 0.30, blue: 0.22))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("MessageBubbleLabDemoContent")
                }
                .accessibilityIdentifier("MessageBubbleLabDemoBubble")
            }
            .frame(maxWidth: .infinity, minHeight: 210)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var liveOutputSection: some View {
        labSection("Live Output") {
            Text(state.output)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.24, green: 0.22, blue: 0.28))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("MessageBubbleLabOutput")
        }
    }

    private var presetsSection: some View {
        labSection("Presets") {
            LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 8) {
                ForEach(MessageBubbleTailPreset.allCases) { preset in
                    Button {
                        state.applyPreset(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(state.selectedPreset == preset ? .white : AppTheme.blue)
                            .background(state.selectedPreset == preset ? AppTheme.blue : Color(red: 0.94, green: 0.97, blue: 1.0), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("MessageBubbleLabPreset_\(preset.rawValue)")
                }
            }
        }
    }

    private var boxControls: some View {
        labSection("Box") {
            VStack(spacing: 8) {
                controlRow("Width", value: state.width, unit: "pt", minusID: "MessageBubbleLabWidthMinus", plusID: "MessageBubbleLabWidthPlus") {
                    state.adjustBox(\.width, by: -10, min: 40)
                } onPlus: {
                    state.adjustBox(\.width, by: 10, min: 40)
                }
                controlRow("Height", value: state.height, unit: "pt", minusID: "MessageBubbleLabHeightMinus", plusID: "MessageBubbleLabHeightPlus") {
                    state.adjustBox(\.height, by: -10, min: 40)
                } onPlus: {
                    state.adjustBox(\.height, by: 10, min: 40)
                }
                controlRow("Padding X", value: state.paddingX, unit: "pt", minusID: "MessageBubbleLabPaddingXMinus", plusID: "MessageBubbleLabPaddingXPlus") {
                    state.adjustBox(\.paddingX, by: -2, min: 0)
                } onPlus: {
                    state.adjustBox(\.paddingX, by: 2, min: 0)
                }
                controlRow("Padding Y", value: state.paddingY, unit: "pt", minusID: "MessageBubbleLabPaddingYMinus", plusID: "MessageBubbleLabPaddingYPlus") {
                    state.adjustBox(\.paddingY, by: -2, min: 0)
                } onPlus: {
                    state.adjustBox(\.paddingY, by: 2, min: 0)
                }
                controlRow("Radius", value: state.radius, unit: "pt", minusID: "MessageBubbleLabRadiusMinus", plusID: "MessageBubbleLabRadiusPlus") {
                    state.adjustBox(\.radius, by: -2, min: 0)
                } onPlus: {
                    state.adjustBox(\.radius, by: 2, min: 0)
                }
                controlRow("Border", value: state.borderWidth, unit: "pt", minusID: "MessageBubbleLabBorderMinus", plusID: "MessageBubbleLabBorderPlus") {
                    state.adjustBox(\.borderWidth, by: -1, min: 0)
                } onPlus: {
                    state.adjustBox(\.borderWidth, by: 1, min: 0)
                }
            }
        }
    }

    private var visualControls: some View {
        labSection("Visual") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Fill / Stroke")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 96, alignment: .leading)
                    Button(state.fillColor.rawValue) {
                        state.cycleFill()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("MessageBubbleLabFillColor")
                    Button(state.strokeColor.rawValue) {
                        state.cycleStroke()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("MessageBubbleLabStrokeColor")
                    Spacer(minLength: 0)
                }
                Toggle("Shadow enabled", isOn: $state.shadowEnabled)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .accessibilityIdentifier("MessageBubbleLabShadowToggle")
                controlRow("Shadow R", value: state.shadowRadius, unit: "pt", minusID: "MessageBubbleLabShadowRadiusMinus", plusID: "MessageBubbleLabShadowRadiusPlus") {
                    state.adjustBox(\.shadowRadius, by: -2, min: 0)
                } onPlus: {
                    state.adjustBox(\.shadowRadius, by: 2, min: 0)
                }
                controlRow("Shadow X", value: state.shadowOffsetX, unit: "pt", minusID: "MessageBubbleLabShadowXMinus", plusID: "MessageBubbleLabShadowXPlus") {
                    state.adjustBox(\.shadowOffsetX, by: -2, min: -80)
                } onPlus: {
                    state.adjustBox(\.shadowOffsetX, by: 2, min: -80)
                }
                controlRow("Shadow Y", value: state.shadowOffsetY, unit: "pt", minusID: "MessageBubbleLabShadowYMinus", plusID: "MessageBubbleLabShadowYPlus") {
                    state.adjustBox(\.shadowOffsetY, by: -2, min: -80)
                } onPlus: {
                    state.adjustBox(\.shadowOffsetY, by: 2, min: -80)
                }
            }
        }
    }

    private var coordinateControls: some View {
        labSection("Tail Points") {
            VStack(spacing: 8) {
                pointRow("Base start", point: state.tail.baseStart, pointKey: \.baseStart, minusPrefix: "MessageBubbleLabBaseStart")
                pointRow("Base end", point: state.tail.baseEnd, pointKey: \.baseEnd, minusPrefix: "MessageBubbleLabBaseEnd")
                pointRow("Tip", point: state.tail.tip, pointKey: \.tip, minusPrefix: "MessageBubbleLabTip")
            }
        }
    }

    private func pointRow(
        _ title: String,
        point: MessageBubblePoint,
        pointKey: WritableKeyPath<MessageBubbleTail, MessageBubblePoint>,
        minusPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            controlRow("x", value: point.x, unit: "pt", minusID: "\(minusPrefix)XMinus", plusID: "\(minusPrefix)XPlus") {
                state.adjustTail(pointKey, axis: \.x, by: -2)
            } onPlus: {
                state.adjustTail(pointKey, axis: \.x, by: 2)
            }
            controlRow("y", value: point.y, unit: "pt", minusID: "\(minusPrefix)YMinus", plusID: "\(minusPrefix)YPlus") {
                state.adjustTail(pointKey, axis: \.y, by: -2)
            } onPlus: {
                state.adjustTail(pointKey, axis: \.y, by: 2)
            }
        }
    }

    private func labSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.985, green: 0.985, blue: 0.99), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(red: 0.88, green: 0.88, blue: 0.91), lineWidth: 1)
        )
    }

    private func controlRow(
        _ title: String,
        value: CGFloat,
        unit: String,
        minusID: String,
        plusID: String,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.27, green: 0.25, blue: 0.32))
                .frame(width: 96, alignment: .leading)
            Button(action: onMinus) {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .heavy))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(minusID)
            Text(format(value))
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 62, height: 30)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(red: 0.86, green: 0.86, blue: 0.90), lineWidth: 1)
                )
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(plusID)
            Text(unit)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}

private struct MessageBubbleLabState {
    var width = MessageBubbleBox.bossStyle.width
    var height = MessageBubbleBox.bossStyle.height
    var radius: CGFloat = 18
    var borderWidth = MessageBubbleBox.bossStyle.borderWidth
    var paddingX: CGFloat = 10
    var paddingY: CGFloat = 10
    var fillColor = MessageBubbleLabColor.bossFill
    var strokeColor = MessageBubbleLabColor.bossStroke
    var shadowEnabled = true
    var shadowRadius: CGFloat = 12
    var shadowOffsetX: CGFloat = 0
    var shadowOffsetY: CGFloat = 4
    var selectedPreset = MessageBubbleTailPreset.bottomRight
    var tail = MessageBubbleTail.bossStyleDefault

    var shadow: MessageBubbleShadow {
        guard shadowEnabled else {
            return MessageBubbleShadow(radius: 0, color: .clear, offsetX: 0, offsetY: 0)
        }
        return MessageBubbleShadow(radius: shadowRadius, color: .black.opacity(0.14), offsetX: shadowOffsetX, offsetY: shadowOffsetY)
    }

    var output: String {
        """
        preset: \(selectedPreset.rawValue)
        unit: pt
        tail: {
          baseStart: { x: \(format(tail.baseStart.x)), y: \(format(tail.baseStart.y)) },
          baseEnd: { x: \(format(tail.baseEnd.x)), y: \(format(tail.baseEnd.y)) },
          tip: { x: \(format(tail.tip.x)), y: \(format(tail.tip.y)) }
        }
        shadow: {
          radius: \(format(shadowRadius)),
          offsetX: \(format(shadowOffsetX)),
          offsetY: \(format(shadowOffsetY))
        }
        """
    }

    mutating func applyPreset(_ preset: MessageBubbleTailPreset) {
        selectedPreset = preset
        tail = MessageBubbleTail.preset(preset, box: labBox)
    }

    mutating func adjustBox(_ keyPath: WritableKeyPath<MessageBubbleLabState, CGFloat>, by delta: CGFloat, min minValue: CGFloat) {
        self[keyPath: keyPath] = max(self[keyPath: keyPath] + delta, minValue)
    }

    mutating func adjustTail(
        _ pointPath: WritableKeyPath<MessageBubbleTail, MessageBubblePoint>,
        axis axisPath: WritableKeyPath<MessageBubblePoint, CGFloat>,
        by delta: CGFloat
    ) {
        tail[keyPath: pointPath][keyPath: axisPath] += delta
    }

    mutating func cycleFill() {
        fillColor = fillColor.nextFill
    }

    mutating func cycleStroke() {
        strokeColor = strokeColor.nextStroke
    }

    private var labBox: MessageBubbleBox {
        MessageBubbleBox(width: width, height: height, borderWidth: borderWidth, tailBase: 24, tailLength: 16, inset: 28, tipInset: 12)
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}

private enum MessageBubbleLabColor: String, CaseIterable {
    case lavender = "#EEE6FF"
    case bossFill = "#FFFDF6"
    case paleBlue = "#E8F4FF"
    case paleRed = "#FCEAEA"
    case paleGreen = "#E8F8EE"
    case purple = "#8B5CF6"
    case bossStroke = "#E7D7B6"
    case blue = "#4A90E2"
    case red = "#E63946"
    case green = "#2E8B57"

    var color: Color {
        switch self {
        case .lavender:
            return Color(red: 0.933, green: 0.902, blue: 1.0)
        case .bossFill:
            return MessageBubbleColor.bossFill
        case .paleBlue:
            return Color(red: 0.91, green: 0.957, blue: 1.0)
        case .paleRed:
            return Color(red: 0.988, green: 0.918, blue: 0.918)
        case .paleGreen:
            return Color(red: 0.91, green: 0.973, blue: 0.933)
        case .purple:
            return Color(red: 0.545, green: 0.361, blue: 0.965)
        case .bossStroke:
            return MessageBubbleColor.bossStroke
        case .blue:
            return Color(red: 0.29, green: 0.565, blue: 0.886)
        case .red:
            return Color(red: 0.902, green: 0.224, blue: 0.275)
        case .green:
            return Color(red: 0.18, green: 0.545, blue: 0.341)
        }
    }

    var nextFill: MessageBubbleLabColor {
        let fills: [MessageBubbleLabColor] = [.lavender, .bossFill, .paleBlue, .paleRed, .paleGreen]
        return next(in: fills)
    }

    var nextStroke: MessageBubbleLabColor {
        let strokes: [MessageBubbleLabColor] = [.purple, .bossStroke, .blue, .red, .green]
        return next(in: strokes)
    }

    private func next(in colors: [MessageBubbleLabColor]) -> MessageBubbleLabColor {
        guard let index = colors.firstIndex(of: self) else {
            return colors[0]
        }
        return colors[(index + 1) % colors.count]
    }
}

#Preview {
    MessageBubbleLabView(coordinator: AppCoordinator())
}

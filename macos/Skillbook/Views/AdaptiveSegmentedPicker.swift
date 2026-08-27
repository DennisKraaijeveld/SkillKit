import SwiftUI

enum SegmentedPickerRole {
    case tab
    case choice

    fileprivate var spacing: CGFloat {
        switch self {
        case .tab: 6
        case .choice: 4
        }
    }

    fileprivate var horizontalPadding: CGFloat {
        switch self {
        case .tab: 14
        case .choice: 12
        }
    }

    fileprivate var height: CGFloat {
        switch self {
        case .tab: 30
        case .choice: 26
        }
    }

    fileprivate var cornerRadius: CGFloat {
        switch self {
        case .tab: 10
        case .choice: 9
        }
    }
}

struct AdaptiveSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let values: [Value]
    let role: SegmentedPickerRole
    let showsLabel: Bool
    let optionTitle: (Value) -> String
    let systemImage: (Value) -> String?

    init(
        _ title: String,
        selection: Binding<Value>,
        values: [Value],
        role: SegmentedPickerRole = .choice,
        showsLabel: Bool = true,
        optionTitle: @escaping (Value) -> String,
        systemImage: @escaping (Value) -> String? = { _ in nil }
    ) {
        self.title = title
        _selection = selection
        self.values = values
        self.role = role
        self.showsLabel = showsLabel
        self.optionTitle = optionTitle
        self.systemImage = systemImage
    }

    var body: some View {
        if showsLabel {
            LabeledContent {
                segmentedControl
            } label: {
                Text(title)
                    .accessibilityHidden(true)
            }
        } else {
            segmentedControl
        }
    }

    private var segmentedControl: some View {
        UnifiedSegmentedControl(
            title,
            selection: $selection,
            values: values,
            role: role,
            equalWidths: true,
            optionTitle: optionTitle,
            systemImage: systemImage
        )
    }
}

struct UnifiedSegmentedControl<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Binding private var selection: Value
    @State private var hoveredValue: Value?

    private let title: String
    private let values: [Value]
    private let role: SegmentedPickerRole
    private let equalWidths: Bool
    private let optionTitle: (Value) -> String
    private let systemImage: (Value) -> String?

    init(
        _ title: String,
        selection: Binding<Value>,
        values: [Value],
        role: SegmentedPickerRole = .tab,
        equalWidths: Bool = false,
        optionTitle: @escaping (Value) -> String,
        systemImage: @escaping (Value) -> String? = { _ in nil }
    ) {
        self.title = title
        _selection = selection
        self.values = values
        self.role = role
        self.equalWidths = equalWidths
        self.optionTitle = optionTitle
        self.systemImage = systemImage
    }

    var body: some View {
        let trackShape = RoundedRectangle(cornerRadius: role.cornerRadius, style: .continuous)

        HStack(spacing: role.spacing) {
            ForEach(values, id: \.self) { value in
                optionButton(for: value)
            }
        }
        .padding(3)
        .background {
            trackShape.fill(SkillbookTheme.segmentedTrack)
        }
        .onMoveCommand(perform: moveSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(optionTitle(selection))
    }

    private func optionButton(for value: Value) -> some View {
        let isSelected = selection == value
        let selectionShape = RoundedRectangle(
            cornerRadius: role.cornerRadius - 3,
            style: .continuous
        )

        return Button {
            select(value)
        } label: {
            optionLabel(for: value, isSelected: isSelected)
                .background {
                    if isSelected {
                        selectionShape
                            .fill(SkillbookTheme.segmentedSelectedFill)
                            .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                    } else if hoveredValue == value, isEnabled {
                        selectionShape.fill(SkillbookTheme.segmentedHoverFill)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredValue = hovering ? value : nil
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func optionLabel(for value: Value, isSelected: Bool) -> some View {
        Group {
            if let systemImage = systemImage(value) {
                Label(optionTitle(value), systemImage: systemImage)
            } else {
                Text(optionTitle(value))
            }
        }
        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
        .lineLimit(1)
        .foregroundStyle(
            isEnabled
                ? (isSelected ? SkillbookTheme.segmentedSelectedLabel : SkillbookTheme.segmentedLabel)
                : SkillbookTheme.segmentedDisabledLabel
        )
        .padding(.horizontal, role.horizontalPadding)
        .frame(maxWidth: equalWidths ? .infinity : nil)
        .frame(height: role.height)
        .contentShape(
            RoundedRectangle(cornerRadius: role.cornerRadius - 3, style: .continuous)
        )
    }

    private func select(_ value: Value) {
        guard selection != value else { return }

        if reduceMotion {
            selection = value
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                selection = value
            }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard isEnabled, let index = values.firstIndex(of: selection) else { return }

        let nextIndex: Int
        switch direction {
        case .left:
            nextIndex = max(values.startIndex, index - 1)
        case .right:
            nextIndex = min(values.index(before: values.endIndex), index + 1)
        default:
            return
        }

        select(values[nextIndex])
    }
}

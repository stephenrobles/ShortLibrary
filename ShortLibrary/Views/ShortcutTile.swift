import SwiftUI

/// Grid card styled after Shortcuts' own tiles: 3:2 color field, glyph badge top-left, name at the bottom.
struct ShortcutTile: View {
    let item: ShortcutItem
    var isSelected: Bool
    @State private var hovering = false
    private var runner = ShortcutRunner.shared

    init(item: ShortcutItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
    }

    /// Proportions measured from Shortcuts' own grid, expressed relative to the tile width.
    private static let aspect: CGFloat = 1.46

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shape = RoundedRectangle(cornerRadius: w * 0.145, style: .continuous)
            ZStack(alignment: .topLeading) {
                shape.fill(item.tileGradient)
                shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        ShortcutIconView(item: item, size: w * 0.142, style: .badge)
                        Spacer(minLength: 0)
                        if runner.isRunning(item) {
                            ProgressView().controlSize(.small).tint(.white)
                        } else if hovering {
                            Button {
                                runner.run(item)
                            } label: {
                                ZStack {
                                    Circle().fill(.white)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: w * 0.075, weight: .bold))
                                        .foregroundStyle(item.tileColor.color)
                                        .offset(x: w * 0.006)
                                }
                                .frame(width: w * 0.145, height: w * 0.145)
                            }
                            .buttonStyle(.plain)
                            .help("Run \(item.name)")
                        } else if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: w * 0.075, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    Spacer(minLength: 4)
                    Text(item.name)
                        .font(.system(size: w * 0.097, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .lineSpacing(-1)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.tagList.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(item.tagList.prefix(5)) { tag in
                                Circle().fill(Color(hex: tag.colorHex)).frame(width: w * 0.04, height: w * 0.04)
                                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 0.5))
                            }
                        }
                        .padding(.top, 3)
                    }
                }
                .padding(.horizontal, w * 0.113)
                .padding(.top, w * 0.09)
                .padding(.bottom, w * 0.10)
                if isSelected {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2.5)
                    shape.inset(by: 2.5).strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .opacity(item.isMissing ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }
}

/// Compact row for list mode.
struct ShortcutRow: View {
    let item: ShortcutItem
    var isSelected: Bool
    @State private var hovering = false
    private var runner = ShortcutRunner.shared

    init(item: ShortcutItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 12) {
            ShortcutIconView(item: item, size: 32, style: .standalone)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                    if item.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    if item.isMissing { Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 6) {
                    Text(item.subtitle.isEmpty ? "\(item.actionCount) actions" : item.subtitle)
                    if let folder = item.folder { Text("·"); Text(folder.name) }
                    if !item.nativeFolderName.isEmpty && item.folder == nil { Text("·"); Text(item.nativeFolderName) }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(item.tagList.prefix(4)) { tag in
                    Text(tag.name)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: tag.colorHex).opacity(0.18), in: Capsule())
                        .foregroundStyle(Color(hex: tag.colorHex))
                }
            }
            if let lastRun = item.lastRunAt {
                Text(lastRun, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.tertiary).frame(width: 90, alignment: .trailing)
            }
            if runner.isRunning(item) { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

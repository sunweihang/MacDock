import AppKit
import SwiftUI

/// 横向长条：左图标 + 右标题（可选）
struct DockLongBarLabel: View {
    let icon: NSImage
    let title: String?
    let showTitle: Bool
    let iconSize: CGFloat
    let barWidth: CGFloat
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)

            if showTitle, let title {
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: barWidth, height: iconSize + 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.06))
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)
                    .padding(.leading, 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }
}

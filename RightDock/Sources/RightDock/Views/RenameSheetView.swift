import SwiftUI

struct RenameSheetHost: View {
    let defaultTitle: String
    let currentDisplayTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(
        defaultTitle: String,
        currentDisplayTitle: String,
        initialText: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.defaultTitle = defaultTitle
        self.currentDisplayTitle = currentDisplayTitle
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        RenameSheetView(
            defaultTitle: defaultTitle,
            currentDisplayTitle: currentDisplayTitle,
            text: $text,
            onSave: {
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                onSave(name)
            },
            onCancel: onCancel
        )
    }
}

struct RenameSheetView: View {
    let defaultTitle: String
    let currentDisplayTitle: String
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("自定义名称")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                nameRow(label: "系统默认", value: defaultTitle)
                nameRow(label: "当前显示", value: currentDisplayTitle)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            TextField("新的显示名称", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .onAppear {
                    DispatchQueue.main.async {
                        nameFieldFocused = true
                    }
                }

            Text("仅改变 Dock 中的显示，不影响窗口标题")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 272)
    }

    private func nameRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

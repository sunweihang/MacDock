import AppKit
import UniformTypeIdentifiers

/// 从拖放粘贴板解析 .app 路径（Finder、程序坞、启动台拖出格式不一）
enum AppDropPasteboard {
    static let dragTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType("public.file-url"),
        NSPasteboard.PasteboardType("public.url"),
        NSPasteboard.PasteboardType("public.item"),
        NSPasteboard.PasteboardType("public.data"),
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        NSPasteboard.PasteboardType("com.apple.application-bundle"),
        NSPasteboard.PasteboardType("com.apple.finder.node"),
        NSPasteboard.PasteboardType(UTType.application.identifier),
        NSPasteboard.PasteboardType(UTType.fileURL.identifier),
    ]

    private static let acceptedTypes = Set(dragTypes)

    /// 悬停阶段：只读类型列表，避免 `readObjects` 阻塞主线程导致光标卡顿
    static func quickAcceptsApplicationDrag(_ pasteboard: NSPasteboard) -> Bool {
        guard pasteboard.pasteboardItems?.isEmpty == false else { return false }
        guard let types = pasteboard.types, !types.isEmpty else { return true }
        if types.contains(where: { acceptedTypes.contains($0) }) {
            return true
        }
        for type in types {
            if let text = pasteboard.string(forType: type), text.contains(".app") {
                return true
            }
        }
        return true
    }

    static func applicationURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            let path = url.path
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            urls.append(url)
        }

        func ingestString(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let url = urlFromPasteboardString(trimmed) {
                add(url)
            }
        }

        let legacyTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.file-url"),
            .fileURL,
            NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        ]
        for type in legacyTypes {
            if let paths = pasteboard.propertyList(forType: type) as? [String] {
                paths.forEach { ingestString($0) }
            }
            if let raw = pasteboard.string(forType: type) {
                ingestString(raw)
            }
            if let data = pasteboard.data(forType: type),
               let raw = String(data: data, encoding: .utf8) {
                ingestString(raw)
            }
        }

        if urls.isEmpty,
           let items = pasteboard.readObjects(forClasses: [NSURL.self], options: [
               .urlReadingFileURLsOnly: true,
           ]) as? [URL] {
            items.forEach(add)
        }

        return urls.filter { $0.pathExtension == "app" || $0.path.hasSuffix(".app") }
    }

    private static func urlFromPasteboardString(_ raw: String) -> URL? {
        if raw.hasPrefix("file://") {
            if let url = URL(string: raw) {
                return url.isFileURL ? url : URL(fileURLWithPath: url.path)
            }
            let path = raw
                .replacingOccurrences(of: "file://", with: "")
                .removingPercentEncoding ?? raw
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }
}

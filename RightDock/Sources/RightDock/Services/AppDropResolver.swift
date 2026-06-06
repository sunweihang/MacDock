import AppKit
import UniformTypeIdentifiers

@MainActor
enum AppDropResolver {
    struct ResolvedApp {
        let bundleIdentifier: String
        let displayName: String
    }

    static func resolve(providers: [NSItemProvider]) async -> [ResolvedApp] {
        var results: [ResolvedApp] = []
        for provider in providers {
            if let app = await resolve(provider: provider) {
                results.append(app)
            }
        }
        return results
    }

    static func resolve(provider: NSItemProvider) async -> ResolvedApp? {
        let types = [
            UTType.fileURL.identifier,
            UTType.application.identifier,
            "com.apple.application-bundle",
            NSPasteboard.PasteboardType.fileURL.rawValue,
        ]

        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            if let app = await load(from: provider, typeIdentifier: type) {
                return app
            }
        }
        return nil
    }

    private static func load(from provider: NSItemProvider, typeIdentifier: String) async -> ResolvedApp? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil)
            if let url = item as? URL {
                return resolveAppURL(url)
            }
            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                return resolveAppURL(url)
            }
            if let string = item as? String {
                return resolveAppURL(URL(fileURLWithPath: string))
            }
            if let nsurl = item as? NSURL {
                return resolveAppURL(nsurl as URL)
            }
        } catch {
            return nil
        }
        return nil
    }

    static func resolveAppURL(_ url: URL) -> ResolvedApp? {
        let appURL = url
        guard appURL.pathExtension == "app" else { return nil }

        if !FileManager.default.fileExists(atPath: appURL.path) {
            return nil
        }

        guard let bundle = Bundle(url: appURL),
              let bundleId = bundle.bundleIdentifier else {
            return nil
        }

        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent

        return ResolvedApp(bundleIdentifier: bundleId, displayName: name)
    }
}

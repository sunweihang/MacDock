import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: DockSettings
    @ObservedObject var runningApps: RunningAppsService
    @State private var newBundleId = ""

    var body: some View {
        Form {
            Section("外观") {
                Picker("图标大小", selection: $settings.iconSize) {
                    ForEach(DockIconSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }

                Toggle("上区显示标题", isOn: $settings.showTitles)

                Toggle("替换系统程序坞（Option+绿键填满与 RightDock 对齐）", isOn: $settings.replaceSystemDock)

                Text("需开启此项。仅 Option+点绿色按钮「填满屏幕」时，窗口右缘会对齐 Dock 左缘；普通绿键 Zoom 不干预。原生全屏（⌃⌘F）会先自动退出再对齐。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("恢复前台窗口标题栏") {
                    NotificationCenter.default.post(name: .rightDockRestoreTitleBar, object: nil)
                }

                Text("Cursor 等若缺少左上角红黄绿：先点上方按钮，或在应用内按 ⌃⌘F；也可右键本 Dock 面板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Dock 宽度")
                        Spacer()
                        Text("\(settings.barWidthInt) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $settings.barWidth,
                        in: DockSettings.barWidthMin...DockSettings.barWidthMax,
                        step: DockSettings.barWidthStep
                    )

                    HStack(spacing: 12) {
                        TextField("宽度", value: $settings.barWidthInt, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                        Stepper("", value: $settings.barWidthInt,
                                in: Int(DockSettings.barWidthMin)...Int(DockSettings.barWidthMax),
                                step: Int(DockSettings.barWidthStep))
                        .labelsHidden()

                        Button("默认 (\(Int(DockSettings.barWidthDefault)))") {
                            settings.barWidth = DockSettings.barWidthDefault
                        }
                        .buttonStyle(.borderless)
                    }

                    Text("也可拖拽 Dock 左边缘调节宽度，范围 \(Int(DockSettings.barWidthMin))–\(Int(DockSettings.barWidthMax)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("固定快捷方式") {
                List {
                    ForEach(settings.pinnedApps) { app in
                        HStack {
                            Image(nsImage: AppLauncher.icon(for: app))
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(app.displayName)
                            Spacer()
                            Text(app.folderPath ?? app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: settings.removePinned)
                    .onMove(perform: settings.movePinned)
                }
                .frame(minHeight: 120)

                HStack {
                    TextField("Bundle ID，如 com.apple.Safari", text: $newBundleId)
                    Button("添加") {
                        let id = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !id.isEmpty else { return }
                        let name = AppLauncher.displayName(forBundleIdentifier: id)
                        settings.addPinned(bundleIdentifier: id, displayName: name)
                        newBundleId = ""
                    }
                    .disabled(newBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Menu("从运行中的应用添加") {
                    ForEach(runningApps.uniqueRunningBundles, id: \.bundleId) { entry in
                        Button(entry.name) {
                            settings.addPinned(
                                bundleIdentifier: entry.bundleId,
                                displayName: entry.name
                            )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 480)
        .padding()
    }
}

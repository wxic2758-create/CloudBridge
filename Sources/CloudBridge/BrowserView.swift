import SwiftUI

struct BrowserView: View {
    @Environment(BrowserModel.self) private var model
    @State private var workspace = Workspace.servers
    @State private var searchText = ""
    @State private var itemFilter = ItemFilter.all

    private enum Workspace: Hashable {
        case servers
        case tasks
        case settings

        var title: String {
            switch self {
            case .servers: "服务器"
            case .tasks: "下载任务"
            case .settings: "设置"
            }
        }
    }

    private enum ItemFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case folders = "文件夹"
        case files = "文件"

        var id: Self { self }
    }

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            sidebar(model: model)
        } detail: {
            mainWorkspace(model: model)
        }
        .background(WindowTitleUpdater(title: workspace.title))
        .sheet(isPresented: $model.isShowingServerEditor) {
            ServerEditor(model: model)
        }
        .alert("CloudBridge", isPresented: errorPresented(model: model)) {
            if model.pendingHostKey != nil {
                Button("信任并继续") {
                    model.approvePendingHostKey()
                }
                Button("取消", role: .cancel) {
                    model.rejectPendingHostKey()
                }
            } else {
                Button("好", role: .cancel) {}
            }
        } message: {
            Text(model.pendingHostKey?.confirmationDescription ?? model.errorMessage ?? "发生未知错误。")
        }
    }

    private func sidebar(model: BrowserModel) -> some View {
        @Bindable var model = model

        return VStack(spacing: 0) {
            brandHeader

            VStack(alignment: .leading, spacing: 3) {
                Text("工作区")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 3)
                workspaceRow("服务器", icon: "server.rack", destination: .servers)
                workspaceRow("下载任务", icon: "arrow.down.circle", destination: .tasks, count: model.downloadTasks.count)
                workspaceRow("设置", icon: "gearshape", destination: .settings)
            }
            .padding(.bottom, 10)

            Divider()

            List(selection: $model.selectedServerID) {
                Section("我的服务器") {
                    ForEach(model.savedServers) { server in
                        ServerRow(
                            server: server,
                            isConnected: model.isConnected && server.id == model.selectedServerID
                        )
                        .tag(server.id)
                        .contextMenu {
                            Button("编辑服务器") {
                                model.selectedServerID = server.id
                                model.editSelectedServer()
                            }
                            Button("移除服务器", role: .destructive) {
                                model.selectedServerID = server.id
                                model.deleteSelectedServer()
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .padding(.top, 12)
            .onChange(of: model.selectedServerID) { _, id in
                model.selectSavedServer(id)
                workspace = .servers
            }
            .disabled(model.isConnected || model.isBusy)

            Button {
                model.newServer()
            } label: {
                Label("添加服务器", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .disabled(model.isConnected || model.isBusy)
        }
        .navigationSplitViewColumnWidth(min: 245, ideal: 270, max: 310)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("CloudBridge")
                    .font(.system(size: 16, weight: .semibold))
                Text("远程下载管理")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func workspaceRow(
        _ title: String,
        icon: String,
        destination: Workspace,
        count: Int? = nil
    ) -> some View {
        Button {
            workspace = destination
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(workspace == destination ? Color.accentColor : .primary)
        }
        .font(.body)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func mainWorkspace(model: BrowserModel) -> some View {
        switch workspace {
        case .servers:
            serverWorkspace(model: model)
        case .tasks:
            tasksWorkspace(model: model)
        case .settings:
            settingsWorkspace(model: model)
        }
    }

    private func serverWorkspace(model: BrowserModel) -> some View {
        VStack(spacing: 0) {
            if model.selectedServer == nil {
                ContentUnavailableView {
                    Label("还没有服务器", systemImage: "server.rack")
                } description: {
                    Text("添加一台服务器后即可浏览远程文件。")
                } actions: {
                    Button("添加服务器") {
                        model.newServer()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                browser(model: model)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func browser(model: BrowserModel) -> some View {
        VStack(spacing: 0) {
            browserHeader(model: model)
            Divider()
            fileTable(model: model)
            Divider()
            selectionBar(model: model)
        }
    }

    private func browserHeader(model: BrowserModel) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(model.isConnected ? .green : .secondary.opacity(0.55))
                    .frame(width: 9, height: 9)
                    .accessibilityLabel(model.isConnected ? "已连接" : "未连接")

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedServer?.displayName ?? "服务器")
                        .font(.system(size: 16, weight: .semibold))
                    Text(model.selectedServer?.endpoint ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isConnected {
                    Button("断开") {
                        model.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)
                } else {
                    Button {
                        model.connect()
                    } label: {
                        Label("连接", systemImage: "bolt.horizontal.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }

                Menu {
                    Button("编辑服务器") {
                        model.editSelectedServer()
                    }
                    Button("移除服务器", role: .destructive) {
                        model.deleteSelectedServer()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("服务器选项")
                .disabled(model.isConnected || model.isBusy)
            }

            HStack(spacing: 8) {
                ControlGroup {
                    Button {
                        model.open(.parent)
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                    }
                    .help("返回上一级")
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(model.isConnected == false || model.currentPath == "." || model.currentPath == "/" || model.isBusy)

                    Button {
                        model.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新当前目录")
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isConnected == false || model.isBusy)
                }

                Label(model.currentPath, systemImage: "folder")
                    .font(.system(size: 14, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            HStack(spacing: 8) {
                TextField("搜索当前目录", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .disabled(model.isConnected == false)

                Picker("文件类型", selection: $itemFilter) {
                    ForEach(ItemFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: 108)
                .disabled(model.isConnected == false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func fileTable(model: BrowserModel) -> some View {
        @Bindable var model = model

        if model.isConnected == false {
            ContentUnavailableView {
                Label("服务器未连接", systemImage: "network.slash")
            } description: {
                Text("连接后即可查看远程文件。")
            } actions: {
                Button("连接") { model.connect() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            Table(filteredItems(model: model), selection: $model.selectedItemID) {
            TableColumn("名称") { item in
                HStack(spacing: 8) {
                    Image(systemName: item.systemImageName)
                        .foregroundStyle(item.isDirectory ? Color.bridgeAccent : Color.secondary)
                        .frame(width: 18)
                    Text(item.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    model.activate(item)
                }
            }

            TableColumn("类型") { item in
                Text(itemType(item))
                    .foregroundStyle(.secondary)
            }
            .width(min: 86, ideal: 104, max: 130)

            TableColumn("大小") { item in
                Text(formattedSize(item.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100, max: 120)

            TableColumn("修改时间") { item in
                Text(formattedDate(item.modifiedAt))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 140, ideal: 170, max: 200)
            }
            .alternatingRowBackgrounds(.enabled)
            .font(.system(size: 14))
            .overlay {
                if model.isLoading {
                    ProgressView("正在读取文件")
                } else if filteredItems(model: model).isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "文件夹为空" : "没有匹配的文件",
                        systemImage: searchText.isEmpty ? "folder" : "magnifyingglass"
                    )
                }
            }
        }
    }

    private func selectionBar(model: BrowserModel) -> some View {
        HStack {
            if let selectedItem = model.selectedItem, selectedItem.name != ".." {
                Text("已选择 1 个项目")
                    .font(.subheadline.weight(.medium))
                Text(selectedItem.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(model.isConnected ? "选择文件后开始下载" : "重新连接后开始下载")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.downloadSelected()
            } label: {
                Label("下载", systemImage: "arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedItem == nil || model.selectedItem?.name == ".." || model.isBusy)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private func tasksWorkspace(model: BrowserModel) -> some View {
        VStack(spacing: 0) {
            if model.downloadTasks.isEmpty {
                ContentUnavailableView(
                    "暂无下载任务",
                    systemImage: "arrow.down.circle",
                    description: Text("从远程浏览器选择项目后开始下载。")
                )
            } else {
                List(model.downloadTasks) { task in
                    DownloadTaskRow(task: task) {
                        model.reveal(task)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsWorkspace(model: BrowserModel) -> some View {
        VStack(spacing: 0) {
            Form {
                Section("下载") {
                    LabeledContent("下载文件夹") {
                        Text(model.localDownloadDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("选择下载文件夹") {
                        model.chooseLocalDirectory()
                    }
                }

                Section("隐私与凭据") {
                    Text("服务器地址、端口和用户名只保存在这台 Mac。密码保存在这台 Mac 的钥匙串中，不会上传到任何服务。")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func filteredItems(model: BrowserModel) -> [RemoteItem] {
        model.items.filter { item in
            let isKindMatch: Bool
            switch itemFilter {
            case .all:
                isKindMatch = true
            case .folders:
                isKindMatch = item.isDirectory
            case .files:
                isKindMatch = item.isDirectory == false
            }

            return isKindMatch && (searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private func itemType(_ item: RemoteItem) -> String {
        switch item.kind {
        case .directory:
            "文件夹"
        case .file:
            "文件"
        case .symlink:
            "链接"
        case .unknown:
            "未知"
        }
    }

    private func errorPresented(model: BrowserModel) -> Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil || model.pendingHostKey != nil },
            set: { isPresented in
                if isPresented == false {
                    model.errorMessage = nil
                    model.rejectPendingHostKey()
                }
            }
        )
    }

    private func formattedSize(_ size: Int64?) -> String {
        guard let size else { return "-" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}

private struct ServerRow: View {
    let server: SavedServer
    let isConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .foregroundStyle(isConnected ? Color.bridgeAccent : .secondary)
                Text(server.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if isConnected {
                    Text("已连接")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            Text(server.endpoint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
    }
}

private struct ServerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: BrowserModel
    @State private var isPasswordVisible = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.editingServer.name.isEmpty ? "添加服务器" : "编辑服务器")
                        .font(.system(size: 20, weight: .semibold))
                    Text("填写连接服务器所需的信息。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                EditorField(label: "服务器名称", hint: "保存在本机，方便识别") {
                    TextField("例如：我的开发服务器", text: $model.editingServer.name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(alignment: .top, spacing: 14) {
                    EditorField(label: "服务器地址") {
                        TextField("IP 地址或域名", text: $model.editingServer.host)
                            .textFieldStyle(.roundedBorder)
                    }

                    EditorField(label: "端口") {
                        TextField("22", value: $model.editingServer.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(width: 112)
                }

                EditorField(label: "用户名", hint: "这是服务器用户名，不是 CloudBridge 账号") {
                    TextField("服务器提供的用户名", text: $model.editingServer.username)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                Text("密码连接")
                    .font(.system(size: 16, weight: .semibold))

                EditorField(label: "密码") {
                    HStack(spacing: 8) {
                        Group {
                            if isPasswordVisible {
                                TextField("保存在这台 Mac 的钥匙串中", text: $model.editingPassword)
                            } else {
                                SecureField("保存在这台 Mac 的钥匙串中", text: $model.editingPassword)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(isPasswordVisible ? "隐藏密码" : "显示密码")
                        .accessibilityLabel(isPasswordVisible ? "隐藏密码" : "显示密码")
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                    Text("服务器配置保存在这台 Mac。密码保存在钥匙串中，不会发送到 CloudBridge 的任何服务。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(28)
            }

            Divider()
            HStack {
                Button("取消") {
                    dismiss()
                }
                .controlSize(.large)
                Spacer()
                Button("保存服务器") {
                    model.saveEditingServer()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(minWidth: 112)
                .keyboardShortcut(.defaultAction)
                .disabled(model.editingServer.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.editingServer.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 560, height: 620)
    }
}

private struct EditorField<Content: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder let content: Content

    init(label: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.callout.weight(.semibold))
            content
                .controlSize(.large)
                .font(.body)
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadTask
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.itemName)
                    .lineLimit(1)
                Text("来自 \(task.serverName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            taskAction
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var taskAction: some View {
        switch task.status {
        case .downloading:
            Text("正在下载")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .completed:
            Button("在 Finder 中显示", action: reveal)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .trailing)
        }
    }
}

#Preview {
    BrowserView()
        .environment(BrowserModel())
        .tint(.bridgeAccent)
}

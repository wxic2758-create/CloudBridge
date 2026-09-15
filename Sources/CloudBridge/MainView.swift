import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers

@MainActor private func copy(_ key: String) -> String { AppLanguage.text(key) }

private enum Finish {
    static let ink = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    // underPageBackgroundColor is intentionally gray on macOS and is too heavy
    // for a file table that should read as the primary content surface.
    static let panelSecondary = Color(nsColor: .textBackgroundColor)
    static let divider = Color(nsColor: .separatorColor)
    static let lilac = Color.bridgeAccent
    static let errorSurface = Color(nsColor: NSColor(name: "CloudBridgeErrorSurface") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        }
        return NSColor(srgbRed: 0.985, green: 0.985, blue: 0.99, alpha: 1)
    })
    static let actionInk = Color(nsColor: NSColor(name: "CloudBridgeActionInk") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.10, green: 0.08, blue: 0.20, alpha: 1.0)
        }
        return NSColor.white
    })
}

private struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(24)
            .background(Finish.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Finish.divider.opacity(0.8)) }
    }
}

private struct SettingsIcon: View {
    enum Kind: String {
        case folder
        case language = "globe"
        case privacy = "lock"
    }

    let kind: Kind

    var body: some View {
        Image(systemName: kind.rawValue)
        .resizable()
        .scaledToFit()
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(Finish.lilac)
        .frame(width: 18, height: 18)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

struct MainView: View {
    @Environment(BrowserModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var section: AppSection
    @State private var query = ""
    @State private var removal = false
    @State private var workspaceFrames: [String: CGRect] = [:]
    @State private var downloadFlight: DownloadFlight?
    @State private var downloadFlightArrived = false
    @State private var downloadTabAcknowledged = false
    @State private var downloadButtonHovered = false
    @State private var downloadAvailabilityRevision = 0
    @State private var hoveredRemoteItemID: RemoteItem.ID?
    @State private var localStatusHoverTarget: String?
    @State private var localStatusHelpTarget: String?
    @State private var localStatusHelpTask: Task<Void, Never>?
    private var canManage: Bool { !model.isConnected && !model.isBusy }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                if section == .downloads { downloads }
                else if section == .settings { SettingsView() }
                else if model.isConnected { files }
                else { connections }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let error = model.errorMessage, !model.isShowingServerEditor {
                    errorBanner(error)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
        }
        .background {
            ZStack(alignment: .top) {
                Finish.ink
                RadialGradient(colors: [Finish.lilac.opacity(0.08), .clear], center: .top, startRadius: 5, endRadius: 520)
            }.ignoresSafeArea()
        }
        .tint(Finish.lilac)
        .sheet(isPresented: Binding(get: { model.previewURL != nil }, set: { if !$0 { model.dismissPreview() } })) {
            if let url = model.previewURL {
                FileContentPreview(url: url, close: model.dismissPreview, download: { model.dismissPreview(); model.downloadSelected() })
            }
        }
        .sheet(isPresented: $model.isShowingServerEditor) { ConnectionEditor(model: model) }
        .confirmationDialog(copy("server.removeTitle"), isPresented: $removal, titleVisibility: .visible) {
            Button(copy("action.removeServer"), role: .destructive, action: model.deleteSelectedServer)
            Button(copy("action.cancel"), role: .cancel) {}
        } message: { Text(copy("server.removeHelp")) }
        .onChange(of: model.currentPath) { _, _ in query = "" }
        .onChange(of: model.isConnected) { _, connected in if connected { section = .servers } }
        .onChange(of: section) { _, value in
            if value == .downloads { downloadAvailabilityRevision &+= 1 }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { downloadAvailabilityRevision &+= 1 }
        }
        .onChange(of: model.lastEnqueuedDownloadTaskID) { _, taskID in
            acknowledgeDownload(taskID)
        }
        .onPreferenceChange(WorkspaceFrames.self) { workspaceFrames = $0 }
        .onDisappear { localStatusHelpTask?.cancel() }
        .coordinateSpace(name: "cloudbridgeWindow")
        .overlay { downloadFlightOverlay.allowsHitTesting(false) }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Finish.lilac)
            Text(error)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canManage, model.selectedServer != nil {
                Button(copy("action.editServer")) {
                    model.errorMessage = nil
                    model.editSelectedServer()
                }
                .buttonStyle(.borderless)
            }
            Button {
                model.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(copy("action.clear"))
            .accessibilityLabel(copy("action.clear"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 720)
        .background(Finish.errorSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Finish.divider.opacity(0.6))
        }
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }

    private var header: some View {
        HStack(spacing: 28) {
            HStack(spacing: 10) {
                Group {
                    if let image = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        BridgeArtwork()
                    }
                }.frame(width: 34, height: 34).accessibilityHidden(true)
                Text("CloudBridge").font(.title3.weight(.semibold))
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(Array([
                    (AppSection.servers, "nav.servers"),
                    (AppSection.downloads, "nav.tasks"),
                    (AppSection.settings, "nav.settings")
                ].enumerated()), id: \.offset) { _, entry in
                    let (destination, key) = entry
                    Button { section = destination } label: {
                        ZStack {
                            Text(copy(key))
                                .frame(maxWidth: destination == .downloads ? 76 : .infinity)
                            if destination == .downloads {
                                Text("\(min(model.activeDownloadCount, 99))")
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Finish.lilac)
                                    .frame(width: 18, height: 16)
                                    .background(Finish.lilac.opacity(0.14), in: Capsule())
                                    .opacity(model.activeDownloadCount > 0 ? 1 : 0)
                                    .accessibilityHidden(model.activeDownloadCount == 0)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: 120, height: 36)
                    }
                    .buttonStyle(.plain)
                    .background(
                        section == destination || (destination == .downloads && downloadTabAcknowledged)
                            ? .white.opacity(0.09) : .clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .background {
                        if destination == .downloads {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: WorkspaceFrames.self,
                                    value: ["destination": proxy.frame(in: .named("cloudbridgeWindow"))]
                                )
                            }
                        }
                    }
                    .foregroundStyle(section == destination ? .primary : .secondary)
                    .accessibilityAddTraits(section == destination ? .isSelected : [])
                }
            }
        }.padding(.horizontal, 30).padding(.vertical, 20)
    }

    private var connections: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 34, weight: .light)).foregroundStyle(Finish.lilac).accessibilityHidden(true)
                    Text(copy("server.emptyTitle")).font(.largeTitle.weight(.medium)).multilineTextAlignment(.center)
                    Text(copy(model.savedServers.isEmpty ? "server.emptyHelp" : "connection.help")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.top, 28)
                VStack(alignment: .leading, spacing: 18) {
                    if !model.savedServers.isEmpty {
                        HStack {
                            Text(copy("sidebar.servers")).font(.headline)
                            Spacer()
                            Menu {
                                Button {
                                    model.errorMessage = nil
                                    model.newServer()
                                } label: {
                                    Label(copy("action.addServer"), systemImage: "plus")
                                }
                                Button {
                                    model.errorMessage = nil
                                    model.editSelectedServer()
                                } label: {
                                    Label(copy("action.editServer"), systemImage: "pencil")
                                }
                                .disabled(model.selectedServer == nil)
                                Button(role: .destructive) { removal = true } label: {
                                    Label(copy("action.removeServer"), systemImage: "trash")
                                }
                                .disabled(model.selectedServer == nil)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 8)
                                    .frame(width: 40, height: 40)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .help(copy("server.options"))
                            .accessibilityLabel(copy("server.options"))
                        }.disabled(!canManage)
                        ForEach(model.savedServers) { server in
                            Button { model.selectSavedServer(server.id) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "server.rack").foregroundStyle(Finish.lilac)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(server.displayName).font(.headline)
                                        Text(server.endpoint).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Image(systemName: model.selectedServerID == server.id ? "checkmark.circle.fill" : "circle").foregroundStyle(Finish.lilac)
                                }.padding(16).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!canManage)
                                .background(.white.opacity(model.selectedServerID == server.id ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 11))
                                .accessibilityAddTraits(model.selectedServerID == server.id ? .isSelected : [])
                        }
                        Button {
                            model.errorMessage = nil
                            model.connect()
                        } label: {
                            HStack { if model.isLoading { ProgressView().controlSize(.small) }; Text(copy(model.isLoading ? "connection.connecting" : "action.connect")) }.frame(maxWidth: .infinity)
                        }.buttonStyle(BridgeActionStyle(prominent: true)).disabled(!canManage || model.selectedServer == nil)
                    } else {
                        Button { model.errorMessage = nil; model.newServer() } label: { Label(copy("action.addServer"), systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(BridgeActionStyle(prominent: true))
                    }
                }.modifier(Panel())
            }.frame(maxWidth: 560).padding(36).frame(maxWidth: .infinity)
        }
    }

    private var visibleItems: [RemoteItem] {
        model.items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var canDownload: Bool { model.canQueueDownloads && !model.selectedItems.isEmpty }
    private var canPreview: Bool { !model.isBusy && model.selectedItems.count == 1 && model.selectedItem?.isDirectory == false }
    private var files: some View {
        @Bindable var model = model
        return VStack(spacing: 22) {
            HStack(spacing: 18) {
                Menu {
                    ForEach(model.savedServers) { server in
                        Button { model.switchServer(to: server.id) } label: {
                            Label(server.displayName, systemImage: server.id == model.selectedServerID ? "checkmark" : "server.rack")
                        }.disabled(model.isBusy || server.id == model.selectedServerID)
                    }
                    Divider()
                    Button(copy("action.addServer"), action: model.newServer).disabled(model.isBusy)
                    Button(copy("action.disconnect"), action: model.disconnect).disabled(model.isBusy)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack").foregroundStyle(Finish.lilac)
                        Text(model.selectedServer?.displayName ?? model.profile.host).font(.headline)
                    }.padding(.vertical, 8)
                }.menuStyle(.borderlessButton).fixedSize().help(copy("nav.servers"))
                Label(copy("connection.connected"), systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button { model.open(.parent) } label: { Image(systemName: "arrow.up").frame(width: 32, height: 32) }
                        .help(copy("action.parent")).accessibilityLabel(copy("action.parent"))
                        .disabled(model.isBusy || model.currentPath == "." || model.currentPath == "/")
                    Image(systemName: "folder").foregroundStyle(Finish.lilac).accessibilityHidden(true)
                    Text(model.currentPath == "." ? "~" : model.currentPath)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer(minLength: 24)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField(copy("browser.search"), text: $query).textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help(copy("action.clearSearch"))
                            .accessibilityLabel(copy("action.clearSearch"))
                        }
                    }.padding(9).frame(width: 220)
                        .background(Finish.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Finish.divider.opacity(0.7)) }
                    Button(action: model.reload) { Image(systemName: "arrow.clockwise").frame(width: 32, height: 32) }
                        .help(copy("action.refresh")).accessibilityLabel(copy("action.refresh")).disabled(model.isBusy)
                }.buttonStyle(.borderless).padding(18)
                    .background(Finish.panel)
                Divider().opacity(0.5)
                Table(visibleItems, selection: $model.selectedItemIDs) {
                    TableColumn(copy("file.name")) { item in
                        HStack(spacing: 12) {
                            RemoteItemIcon(item: item)
                                .frame(width: 24)
                            Text(item.name).lineLimit(1)
                        }
                        .padding(.vertical, 6)
                        .onHover { hovering in
                            if hovering { hoveredRemoteItemID = item.id }
                            else if hoveredRemoteItemID == item.id { hoveredRemoteItemID = nil }
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: WorkspaceFrames.self,
                                    value: ["file:" + item.path: proxy.frame(in: .named("cloudbridgeWindow"))]
                                )
                            }
                        }
                    }
                    TableColumn(copy("file.size")) { item in
                        let size = item.size.map { CompactFileSizeFormatter.string(fromByteCount: $0) } ?? "—"
                        Text(size)
                            .foregroundStyle(.secondary).monospacedDigit()
                    }.width(110)
                    TableColumn(copy("file.modified")) { item in
                        Text(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—").foregroundStyle(.secondary)
                    }.width(180)
                    TableColumn(copy("file.localStatus")) { item in
                        localStatusControl(for: item)
                    }.width(120)
                }
                .alternatingRowBackgrounds(.disabled)
                .scrollContentBackground(.hidden)
                .tableStyle(.inset)
                .contextMenu(forSelectionType: RemoteItem.ID.self) { ids in
                    let selected = model.items.filter { ids.contains($0.id) && $0.name != ".." }
                    if selected.count == 1, let item = selected.first {
                        Button(copy("action.open")) { model.activate(item) }.disabled(model.isBusy)
                        Button(copy("action.preview")) { model.preview(item) }.disabled(model.isBusy || item.isDirectory)
                    }
                    if !selected.isEmpty {
                        Button(copy("action.download")) { model.download(selected) }.disabled(!model.canQueueDownloads)
                    }
                } primaryAction: { ids in
                    if !model.isBusy, ids.count == 1, let id = ids.first,
                       let item = model.items.first(where: { $0.id == id }) { model.activate(item) }
                }
                .onKeyPress(.space) {
                    guard canPreview, let item = model.selectedItem else { return .ignored }
                    model.preview(item)
                    return .handled
                }
                .overlay {
                    if model.isLoading {
                        ProgressView(model.statusMessage).padding(24).background(Finish.ink, in: RoundedRectangle(cornerRadius: 12))
                    } else if visibleItems.isEmpty {
                        Text(copy(query.isEmpty ? "browser.empty" : "browser.noMatch")).foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.5)
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.selectedItems.count > 1, let first = model.selectedItems.first {
                            Text("\(first.name)  +\(model.selectedItems.count - 1)")
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(model.selectedItems.map(\.path).joined(separator: "\n"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else if let selected = model.selectedItem, selected.name != ".." {
                            Text(selected.name).font(.headline).lineLimit(1).truncationMode(.middle)
                            Text(selected.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        } else {
                            Text(copy("tasks.emptyHelp")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button(copy("action.preview")) { if let item = model.selectedItem { model.preview(item) } }
                        .buttonStyle(BridgeActionStyle(prominent: false, compact: true))
                        .disabled(!canPreview)
                    Button(copy("action.download"), action: model.downloadSelected)
                        .buttonStyle(BridgeActionStyle(prominent: true, compact: true))
                        .disabled(!canDownload)
                        .onHover { downloadButtonHovered = $0 }
                }.padding(.horizontal, 18).padding(.vertical, 16)
                    .background(Finish.panel)
            }
            .background(Finish.panelSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Finish.divider.opacity(0.8)).allowsHitTesting(false) }
        }.padding(30)
            .onChange(of: query) { _, _ in
                model.selectedItemIDs.formIntersection(Set(visibleItems.map(\.id)))
            }
    }

    private var downloads: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(copy("tasks.title")).font(.largeTitle.weight(.medium))
                    Spacer()
                    if model.hasDownloadHistory {
                        Button(action: model.clearDownloadHistory) {
                            Label(copy("tasks.clearCompleted"), systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if model.downloadTasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.to.line").font(.largeTitle).foregroundStyle(Finish.lilac)
                        Text(copy("tasks.empty")).font(.title3)
                        Text(copy("tasks.emptyHelp")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.downloadTasks) { task in downloadRow(task) }
                    }
                    .id(downloadAvailabilityRevision)
                }
            }.frame(maxWidth: 780).padding(40).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func downloadRow(_ task: DownloadTask) -> some View {
        let removed = task.status == .completed && !task.destinationExists
        HStack(spacing: 12) {
            RemoteItemIcon(item: taskRemoteItem(task))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.itemName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(removed)
                    .foregroundStyle(removed ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(task.serverName).lineLimit(1)
                    if let completedAt = task.completedAt {
                        Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            switch task.status {
            case .queued:
                downloadProgress(for: task)
                Button { model.cancelDownload(task) } label: {
                    Image(systemName: "xmark.circle").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(copy("action.cancel"))
                .accessibilityLabel(copy("action.cancel"))
            case .downloading:
                downloadProgress(for: task)
                Button { model.pauseDownload(task) } label: {
                    Image(systemName: "pause.circle").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(copy("action.pause"))
                .accessibilityLabel(copy("action.pause"))
                Button { model.cancelDownload(task) } label: {
                    Image(systemName: "xmark.circle").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(copy("action.cancel"))
                .accessibilityLabel(copy("action.cancel"))
            case .paused:
                downloadProgress(for: task)
                Button { model.resumeDownload(task) } label: {
                    Image(systemName: "play.circle").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(copy("action.resume"))
                .accessibilityLabel(copy("action.resume"))
                Button { model.cancelDownload(task) } label: {
                    Image(systemName: "xmark.circle").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(copy("action.cancel"))
                .accessibilityLabel(copy("action.cancel"))
            case .completed:
                Image(systemName: removed ? "exclamationmark.circle" : "checkmark.circle.fill")
                    .foregroundStyle(removed ? Color.secondary : Finish.lilac)
                    .help(copy(removed ? "tasks.fileRemoved" : "tasks.done"))
                    .accessibilityLabel(copy(removed ? "tasks.fileRemoved" : "tasks.done"))
                Button { model.reveal(task) } label: {
                    Image(systemName: "folder").frame(width: 28, height: 28)
                }
                    .buttonStyle(.borderless)
                    .disabled(removed)
                    .help(copy("action.reveal"))
                    .accessibilityLabel(copy("action.reveal"))
            case .cancelled:
                Button { model.removeDownloadRecord(task) } label: {
                    Image(systemName: "xmark.circle").frame(width: 28, height: 28)
                }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(copy("action.clear"))
                    .accessibilityLabel(copy("action.clear"))
                Button { model.retry(task) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                }
                    .buttonStyle(.borderless)
                    .disabled(!model.canRetry(task))
                    .help(copy("action.retry"))
                    .accessibilityLabel(copy("action.retry"))
            case .failed(let error):
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(copy("tasks.failed") + "\n" + error)
                    .accessibilityLabel(copy("tasks.failed"))
                Button { model.retry(task) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                }
                    .buttonStyle(.borderless)
                    .disabled(!model.canRetry(task))
                    .help(copy("action.retry"))
                    .accessibilityLabel(copy("action.retry"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(Finish.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Finish.divider.opacity(0.8))
        }
    }

    private func downloadProgress(for task: DownloadTask) -> some View {
        let awaitingFirstByte = task.status == .downloading && (task.bytesTransferred ?? 0) == 0
        return HStack(spacing: 4) {
            Group {
                if awaitingFirstByte {
                    ProgressView().controlSize(.small)
                } else {
                    Color.clear
                }
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)

            Text(downloadProgressText(task))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
            .frame(width: 70, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(copy(awaitingFirstByte ? "tasks.transferring" : "tasks.progress"))
            .accessibilityValue(downloadProgressText(task))
    }

    private func downloadProgressText(_ task: DownloadTask) -> String {
        if let progress = task.progress {
            return progress.formatted(.percent.precision(.fractionLength(0)))
        }
        if let bytes = task.bytesTransferred, bytes > 0 {
            return CompactFileSizeFormatter.string(fromByteCount: bytes)
        }
        return "0%"
    }

    private func taskRemoteItem(_ task: DownloadTask) -> RemoteItem {
        RemoteItem(
            id: task.remotePath,
            name: task.itemName,
            path: task.remotePath,
            kind: task.isDirectory ? .directory : .file,
            size: nil,
            modifiedAt: nil
        )
    }

    private func downloadHistoryHelp(_ task: DownloadTask) -> String {
        var parts = [copy(task.destinationExists ? "tasks.done" : "tasks.fileRemoved")]
        if let completedAt = task.completedAt {
            parts.append(completedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: "\n")
    }

    @ViewBuilder
    private func localStatusControl(for item: RemoteItem) -> some View {
        let status = model.localFileStatus(for: item)
        let selected = model.selectedItemIDs.contains(item.id)
        switch status {
        case .current:
            localStatusButton("checkmark.circle.fill", itemID: item.id, help: "file.localCurrent", selected: selected) {
                model.revealDownloaded(item)
            }
        case .localCopy:
            localStatusButton("doc.badge.checkmark", itemID: item.id, help: "file.localCopy", selected: selected) {
                model.revealDownloaded(item)
            }
        case .missing:
            localStatusButton("exclamationmark.circle", itemID: item.id, help: "file.localMissing", enabled: model.canQueueDownloads, selected: selected) {
                model.download(item)
            }
        case .remoteUpdated:
            localStatusButton("arrow.clockwise.circle", itemID: item.id, help: "file.remoteUpdated", enabled: model.canQueueDownloads, selected: selected) {
                model.download(item)
            }
        case .none:
            if hoveredRemoteItemID == item.id || model.selectedItemIDs.contains(item.id) {
                localStatusButton("arrow.down.circle", itemID: item.id, help: "action.download", enabled: model.canQueueDownloads, selected: selected) {
                    model.download(item)
                }
            }
        }
    }

    private func localStatusButton(
        _ symbol: String,
        itemID: RemoteItem.ID,
        help key: String,
        enabled: Bool = true,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let target = "\(itemID)|\(key)"
        return Button(action: action) {
            Image(systemName: symbol).frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(selected ? Finish.actionInk : Finish.lilac)
        .disabled(!enabled)
        .accessibilityLabel(copy(key))
        .onHover { hovering in
            localStatusHelpTask?.cancel()
            if hovering {
                localStatusHoverTarget = target
                localStatusHelpTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, localStatusHoverTarget == target else { return }
                    localStatusHelpTarget = target
                }
            } else {
                if localStatusHoverTarget == target { localStatusHoverTarget = nil }
                if localStatusHelpTarget == target { localStatusHelpTarget = nil }
            }
        }
        .popover(
            isPresented: Binding(
                get: { localStatusHelpTarget == target },
                set: { presented in
                    if !presented, localStatusHelpTarget == target { localStatusHelpTarget = nil }
                }
            ),
            arrowEdge: .bottom
        ) {
            Text(copy(key))
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
    }

    @ViewBuilder
    private var downloadFlightOverlay: some View {
        if let flight = downloadFlight {
            Image(systemName: flight.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Finish.lilac)
                .padding(8)
                .background(Finish.panel, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .position(flight.source)
                .offset(
                    x: downloadFlightArrived ? flight.destination.x - flight.source.x : 0,
                    y: downloadFlightArrived ? flight.destination.y - flight.source.y : 0
                )
                .scaleEffect(downloadFlightArrived ? 0.82 : 1)
                .opacity(downloadFlightArrived ? 0 : 0.96)
        }
    }

    private func acknowledgeDownload(_ taskID: DownloadTask.ID?) {
        guard let taskID, let task = model.downloadTasks.first(where: { $0.id == taskID }) else { return }
        downloadTabAcknowledged = true

        if !reduceMotion, downloadButtonHovered,
           let source = workspaceFrames["file:" + task.remotePath],
           let destination = workspaceFrames["destination"] {
            let flight = DownloadFlight(
                symbol: task.isDirectory ? "folder.fill" : "doc.fill",
                source: CGPoint(x: source.midX, y: source.midY),
                destination: CGPoint(x: destination.midX, y: destination.midY)
            )
            downloadFlight = flight
            downloadFlightArrived = false
            Task { @MainActor in
                await Task.yield()
                guard downloadFlight?.id == flight.id else { return }
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.30)) {
                    downloadFlightArrived = true
                }
                try? await Task.sleep(for: .milliseconds(310))
                guard downloadFlight?.id == flight.id else { return }
                downloadFlight = nil
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard model.lastEnqueuedDownloadTaskID == taskID else { return }
            withAnimation(.easeOut(duration: 0.15)) { downloadTabAcknowledged = false }
        }
    }

}

struct SettingsView: View {
    @Environment(BrowserModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var privacyExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(copy("nav.settings")).font(.largeTitle.weight(.medium))
                Text(copy("settings.help")).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        SettingsIcon(kind: .folder)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy("settings.destination")).font(.headline)
                            Text(model.localDownloadDirectory.path)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 16)
                        Button(copy("action.changeFolder"), action: model.chooseLocalDirectory)
                            .buttonStyle(.plain)
                            .disabled(model.isBusy)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).modifier(Panel())
                HStack(spacing: 12) {
                    SettingsIcon(kind: .language)
                    Text(copy("settings.language")).font(.headline)
                    Spacer(minLength: 16)
                    Picker(copy("settings.language"), selection: Binding(get: { AppLanguage.shared.selection }, set: { AppLanguage.shared.selection = $0 })) {
                        Text(copy("settings.languageSystem")).tag("system")
                        ForEach(AppLanguage.supported, id: \.self) { code in
                            Text(Locale(identifier: code).localizedString(forIdentifier: code) ?? code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .buttonStyle(.plain)
                    .accessibilityLabel(copy("settings.language"))
                }.modifier(Panel())
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        SettingsIcon(kind: .privacy)
                        Text(copy("settings.privacy")).font(.headline)
                        Spacer(minLength: 16)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { privacyExpanded.toggle() }
                        } label: {
                            Image(systemName: privacyExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help(copy("settings.privacy"))
                        .accessibilityLabel(copy("settings.privacy"))
                    }
                    if privacyExpanded {
                        Divider().padding(.vertical, 16)
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(copy("settings.credentials")).font(.headline)
                                Text(copy("settings.credentialsHelp"))
                            }
                            Text(copy("settings.previewHelp"))
                            HStack(spacing: 14) {
                                Button {
                                    openURL(URL(string: "https://wxic2758-create.github.io/CloudBridge/privacy.html")!)
                                } label: {
                                    externalLinkLabel(copy("settings.privacyPolicy"))
                                }
                                .foregroundStyle(Finish.lilac)
                                .help(copy("settings.privacyPolicyHint"))
                                Button {
                                    openURL(URL(string: "https://wxic2758-create.github.io/CloudBridge/support.html")!)
                                } label: {
                                    externalLinkLabel(copy("settings.support"))
                                }
                                .foregroundStyle(Finish.lilac)
                                .help(copy("settings.supportHint"))
                            }
                            .buttonStyle(.borderless)
                        }.foregroundStyle(.secondary)
                    }
                }.modifier(Panel())
            }.frame(maxWidth: 680).padding(40).frame(maxWidth: .infinity)
        }
    }

    private func externalLinkLabel(_ title: String) -> some View {
        Label(title, systemImage: "arrow.up.right")
            .labelStyle(.titleAndIcon)
    }
}

private struct ConnectionEditor: View {
    @Bindable var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var advanced = false
    @State private var passwordVisible = false
    @State private var passwordRemoval = false
    private var valid: Bool {
        !model.editingServer.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.editingServer.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...65535).contains(model.editingServer.port)
    }
    private var isExistingServer: Bool {
        model.savedServers.contains { $0.id == model.editingServer.id }
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(copy(isExistingServer ? "action.editServer" : "action.addServer"))
                        .font(.title2.weight(.semibold))

                    VStack(alignment: .leading, spacing: 14) {
                        editorSectionHeader(icon: "person.crop.circle", title: copy("editor.authentication"))
                        VStack(spacing: 0) {
                            editorTextRow(icon: "network", title: copy("editor.host")) {
                                TextField("", text: $model.editingServer.host)
                                    .textFieldStyle(.plain)
                            }
                            Divider().padding(.leading, 38)
                            editorTextRow(icon: "person", title: copy("editor.username")) {
                                TextField("", text: $model.editingServer.username)
                                    .textFieldStyle(.plain)
                            }
                            Divider().padding(.leading, 38)
                            editorTextRow(icon: "key", title: copy("editor.password")) {
                                if isExistingServer && !model.isChangingPassword {
                                    HStack(spacing: 8) {
                                        Text(copy("credentials.savedStatus"))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button(copy("credentials.change")) {
                                            model.isChangingPassword = true
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        Group {
                                            if passwordVisible {
                                                TextField("", text: $model.editingPassword)
                                            } else {
                                                SecureField("", text: $model.editingPassword)
                                            }
                                        }
                                        .textFieldStyle(.plain)
                                        Button {
                                            passwordVisible.toggle()
                                        } label: {
                                            Image(systemName: passwordVisible ? "eye.slash" : "eye")
                                                .frame(width: 24, height: 24)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .help(copy(passwordVisible ? "action.hidePassword" : "action.showPassword"))
                                        .accessibilityLabel(copy(passwordVisible ? "action.hidePassword" : "action.showPassword"))
                                    }
                                }
                            }
                        }
                        if isExistingServer {
                            HStack {
                                Text(copy("credentials.keepHelp"))
                                Spacer()
                                if model.hasSavedPassword(for: model.editingServer) {
                                    Button(copy("credentials.remove"), role: .destructive) {
                                        passwordRemoval = true
                                    }
                                        .buttonStyle(.borderless)
                                }
                            }
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 38)
                        }
                    }
                    .padding(18)
                    .background(Finish.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Finish.divider.opacity(0.75)) }

                    VStack(alignment: .leading, spacing: 14) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { advanced.toggle() }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                editorSectionHeader(icon: "slider.horizontal.3", title: copy("editor.advanced"))
                                Spacer(minLength: 12)
                                Image(systemName: advanced ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(copy("editor.advanced"))
                        if advanced {
                            VStack(spacing: 0) {
                                editorTextRow(icon: "tag", title: copy("editor.name")) {
                                    TextField("", text: $model.editingServer.name)
                                        .textFieldStyle(.plain)
                                }
                                Divider().padding(.leading, 38)
                                editorTextRow(icon: "number", title: copy("editor.port")) {
                                    TextField("", value: $model.editingServer.port, format: .number.grouping(.never))
                                        .textFieldStyle(.plain)
                                }
                                Divider().padding(.leading, 38)
                                editorTextRow(icon: "folder", title: copy("editor.path")) {
                                    TextField("", text: $model.editingServer.defaultRemotePath)
                                        .textFieldStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(Finish.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Finish.divider.opacity(0.65)) }

                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Finish.lilac)
                            .textSelection(.enabled)
                    }
                }
                .padding(28)
            }
            Divider()
            HStack(spacing: 12) {
                Button(copy("action.cancel")) { model.errorMessage = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
                Spacer()
                Button(copy("action.save"), action: model.saveEditingServer)
                    .buttonStyle(BridgeActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid || model.isBusy)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 640, height: 620)
        .background(Finish.ink)
        .confirmationDialog(copy("credentials.removeTitle"), isPresented: $passwordRemoval, titleVisibility: .visible) {
            Button(copy("credentials.remove"), role: .destructive, action: model.removeEditingPassword)
            Button(copy("action.cancel"), role: .cancel) {}
        } message: {
            Text(copy("credentials.removeHelp"))
        }
    }

    @ViewBuilder
    private func editorSectionHeader(icon: String, title: String) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(Finish.lilac)
            Text(title).font(.headline)
        }
    }

    @ViewBuilder
    private func editorTextRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 30)
            Text(title).font(.body)
                .lineLimit(1)
            Spacer(minLength: 16)
            content().frame(width: 280, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}
/// A softly lit rectangular surface, retaining SwiftUI Button semantics.
private struct BridgeActionStyle: ButtonStyle {
    var prominent: Bool
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        ActionSurface(label: configuration.label, prominent: prominent, compact: compact,
                      pressed: configuration.isPressed)
    }

    private struct ActionSurface<Label: View>: View {
        let label: Label
        let prominent: Bool
        let compact: Bool
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var hovered = false

        private var surface: AnyShapeStyle {
            AnyShapeStyle(prominent ? Finish.lilac : Finish.panel)
        }

        var body: some View {
            label
                .font(.system(size: compact ? 14 : 15, weight: .medium))
                .foregroundStyle(prominent ? Finish.actionInk : .primary)
                .padding(.horizontal, compact ? 20 : 24)
                .padding(.vertical, compact ? 9 : 16)
                .frame(minHeight: compact ? 42 : 52)
                .background(surface)
                .overlay {
                    LinearGradient(colors: [.white.opacity(pressed ? 0 : hovered ? 0.16 : 0.07), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Finish.divider.opacity(contrast == .increased ? 1 : 0.8), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(pressed ? 0.08 : prominent ? 0.28 : 0.10),
                        radius: pressed ? 2 : prominent ? 7 : 3,
                        y: pressed ? 1 : prominent ? 3 : 1)
                .brightness(pressed ? -0.09 : 0)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 11))
                .onHover { hovered = $0 }
        }
    }
}

/// Reads only a bounded prefix; large logs cannot exhaust preview memory.
enum PreviewTextLoader {
    static let limit = 2 * 1024 * 1024
    static func load(_ url: URL) -> String? {
        if let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf) || type.conforms(to: .archive) {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1) else { return nil }
        if data.isEmpty { return "" }
        // UTF-16 must carry a byte-order marker. Arbitrary binary is never decoded as text.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.prefix(limit), encoding: .utf16)
        }
        let sample = data.prefix(limit)
        guard !sample.contains(where: { $0 < 0x20 && ![9, 10, 13].contains($0) }) else { return nil }
        // A bounded prefix may end in the middle of a UTF-8 character.
        for trim in 0...min(3, sample.count) {
            if let text = String(data: sample.dropLast(trim), encoding: .utf8) { return text }
        }
        return nil
    }
}

private struct FileContentPreview: View {
    let url: URL
    let close: () -> Void
    let download: () -> Void
    @State private var text: String?
    @State private var loading = true
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(copy("action.download"), action: download)
                Button(copy("action.cancel"), action: close).keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let text {
                PreviewTextView(text: text)
                if ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > PreviewTextLoader.limit {
                    Label("2 MB / " + CompactFileSizeFormatter.string(fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)), systemImage: "doc.text.magnifyingglass").help(copy("action.download")).padding(8)
                }
            } else {
                NativeFilePreview(url: url)
            }
        }.frame(minWidth: 640, idealWidth: 820, minHeight: 480, idealHeight: 620)
            .task(id: url) {
                let value = await Task.detached(priority: .userInitiated) { PreviewTextLoader.load(url) }.value
                guard !Task.isCancelled else { return }
                text = value
                loading = false
            }
    }
}

private struct NativeFilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.previewItem = nil; view.close() }
}

private struct PreviewTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let editor = NSTextView()
        editor.isEditable = false
        editor.isSelectable = true
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textColor = .labelColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 20, height: 20)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
    }
}

// MARK: - Brand artwork
/// Shared vector geometry for the title bar, exported PDF and every app icon size.
struct BridgeSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.224, y: 0.774))
        p.addCurve(to: CGPoint(x: 0.267, y: 0.620), control1: CGPoint(x: 0.260, y: 0.729), control2: CGPoint(x: 0.267, y: 0.680))
        p.addLine(to: CGPoint(x: 0.267, y: 0.440))
        p.addCurve(to: CGPoint(x: 0.500, y: 0.205), control1: CGPoint(x: 0.267, y: 0.308), control2: CGPoint(x: 0.369, y: 0.205))
        p.addCurve(to: CGPoint(x: 0.733, y: 0.440), control1: CGPoint(x: 0.631, y: 0.205), control2: CGPoint(x: 0.733, y: 0.308))
        p.addLine(to: CGPoint(x: 0.733, y: 0.620))
        p.addCurve(to: CGPoint(x: 0.776, y: 0.774), control1: CGPoint(x: 0.733, y: 0.680), control2: CGPoint(x: 0.740, y: 0.729))
        p.addQuadCurve(to: CGPoint(x: 0.767, y: 0.790), control: CGPoint(x: 0.787, y: 0.790))
        p.addLine(to: CGPoint(x: 0.658, y: 0.790))
        p.addQuadCurve(to: CGPoint(x: 0.642, y: 0.779), control: CGPoint(x: 0.646, y: 0.790))
        p.addCurve(to: CGPoint(x: 0.622, y: 0.625), control1: CGPoint(x: 0.623, y: 0.725), control2: CGPoint(x: 0.622, y: 0.683))
        p.addLine(to: CGPoint(x: 0.622, y: 0.442))
        p.addCurve(to: CGPoint(x: 0.500, y: 0.319), control1: CGPoint(x: 0.622, y: 0.373), control2: CGPoint(x: 0.568, y: 0.319))
        p.addCurve(to: CGPoint(x: 0.378, y: 0.442), control1: CGPoint(x: 0.432, y: 0.319), control2: CGPoint(x: 0.378, y: 0.373))
        p.addLine(to: CGPoint(x: 0.378, y: 0.625))
        p.addCurve(to: CGPoint(x: 0.358, y: 0.779), control1: CGPoint(x: 0.378, y: 0.683), control2: CGPoint(x: 0.377, y: 0.725))
        p.addQuadCurve(to: CGPoint(x: 0.342, y: 0.790), control: CGPoint(x: 0.354, y: 0.790))
        p.addLine(to: CGPoint(x: 0.233, y: 0.790))
        p.addQuadCurve(to: CGPoint(x: 0.224, y: 0.774), control: CGPoint(x: 0.213, y: 0.790))
        p.closeSubpath()
        return p.applying(CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY))
    }
}

struct BridgeArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.205, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.135, green: 0.13, blue: 0.165), Color(red: 0.065, green: 0.065, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: size * 0.205, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.035)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.4, size * 0.0015))
                BridgeSilhouette()
                    .fill(LinearGradient(stops: [
                        .init(color: Color(red: 0.81, green: 0.79, blue: 0.98), location: 0),
                        .init(color: Color(red: 0.69, green: 0.66, blue: 0.94), location: 0.48),
                        .init(color: Color(red: 0.62, green: 0.59, blue: 0.88), location: 1)
                    ], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: 1.06, y: 0.95, anchor: .center)
            }
            .padding(size * 0.045)
        }.aspectRatio(1, contentMode: .fit)
    }
}

import XCTest
@testable import CloudBridge

final class ProcessRunnerTests: XCTestCase {
    actor ListingRunner: ProcessRunning {
        private(set) var requests: [ProcessRequest] = []
        private let output: String

        init(output: String = """
            -rw-r--r-- 1 user group 12 Jan 14 12:00 .env
            drwxr-xr-x 2 user group 64 Jan 14 12:00 Documents
            lrwxr-xr-x 1 user group 11 Jan 14 12:00 current -> releases/v1
            prw-r--r-- 1 user group 0 Jan 14 12:00 events.pipe
            """) {
            self.output = output
        }

        func run(_ request: ProcessRequest) async throws -> String {
            requests.append(request)
            return output
        }

        var count: Int { requests.count }
        var latestInput: String? {
            requests.last?.standardInputData.map { String(decoding: $0, as: UTF8.self) }
        }
    }

    final class StreamCollector: @unchecked Sendable {
        let lock = NSLock()
        private var streams: [ProcessOutputStream] = []
        private var stdout = Data()
        private var stderr = Data()

        func append(_ data: Data, stream: ProcessOutputStream) {
            lock.lock()
            defer { lock.unlock() }
            streams.append(stream)
            switch stream {
            case .standardOutput: stdout.append(data)
            case .standardError: stderr.append(data)
            }
        }

        func contains(_ stream: ProcessOutputStream) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return streams.contains(stream)
        }

        func data(for stream: ProcessOutputStream) -> Data {
            lock.lock()
            defer { lock.unlock() }
            return stream == .standardOutput ? stdout : stderr
        }
    }

    func testLanguageSelectionKeepsRegionalVariantsAndSystemFallback() {
        for code in AppLanguage.supported {
            XCTAssertEqual(AppLanguage.resolved(code, preferred: ["en"]), code)
        }
        XCTAssertTrue(AppLanguage.supported.contains("he"))
        XCTAssertTrue(AppLanguage.isRTL("he"))
        XCTAssertEqual(AppLanguage.resolved("system", preferred: ["zh-Hans-CN"]), "zh-CN")
        XCTAssertEqual(AppLanguage.resolved("system", preferred: ["fr-CA"]), "fr-CA")
        XCTAssertEqual(AppLanguage.resolved("obsolete", preferred: ["en"]), "en")
    }

    func testLanguageLookupSwitchesWithoutChangingTheBundleOrRestarting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for (code, value) in [("en", "Settings"), ("zh-CN", "设置")] {
            let directory = root.appendingPathComponent(code + ".lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let table = ["nav.settings": value, "fallback": "English fallback"]
            let data = try PropertyListSerialization.data(fromPropertyList: code == "en" ? table : ["nav.settings": value], format: .xml, options: 0)
            try data.write(to: directory.appendingPathComponent("Localizable.strings"))
        }
        let bundle = try XCTUnwrap(Bundle(path: root.path))
        XCTAssertEqual(AppLanguage.text("nav.settings", selection: "zh-CN", bundle: bundle), "设置")
        XCTAssertEqual(AppLanguage.text("nav.settings", selection: "en", bundle: bundle), "Settings")
        XCTAssertEqual(AppLanguage.text("fallback", selection: "zh-CN", bundle: bundle), "English fallback")
    }

    func testOutputHandlerReceivesBothStreams() async throws {
        let runner = ProcessRunner()
        let collector = StreamCollector()
        _ = try await runner.run(ProcessRequest(
            executable: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2"],
            outputHandler: { data, stream in
                collector.append(data, stream: stream)
            }
        ))
        XCTAssertTrue(collector.contains(.standardOutput))
        XCTAssertTrue(collector.contains(.standardError))
        XCTAssertEqual(collector.data(for: .standardOutput), Data("out".utf8))
        XCTAssertEqual(collector.data(for: .standardError), Data("err".utf8))
    }

    func testProcessControlPausesAndResumesRunningProcess() async throws {
        let runner = ProcessRunner()
        let control = ProcessControl()
        let operation = Task {
            try await runner.run(ProcessRequest(
                executable: "/bin/sleep",
                arguments: ["0.35"],
                processControl: control
            ))
        }

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(control.pause())
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(control.isPaused)
        XCTAssertTrue(control.resume())
        _ = try await operation.value
        XCTAssertFalse(control.isAttached)
    }

    func testCancellingPausedProcessResumesItForTermination() async throws {
        let runner = ProcessRunner()
        let control = ProcessControl()
        let operation = Task {
            try await runner.run(ProcessRequest(
                executable: "/bin/sleep",
                arguments: ["10"],
                processControl: control
            ))
        }

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(control.pause())
        operation.cancel()

        do {
            _ = try await operation.value
            XCTFail("Expected cancellation")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertFalse(control.isAttached)
        XCTAssertFalse(control.isPaused)
    }
    func testRunDrainsLargeStandardOutputAndStandardError() async throws {
        let runner = ProcessRunner()
        let request = ProcessRequest(
            executable: "/bin/sh",
            arguments: [
                "-c",
                """
                i=0
                while [ "$i" -lt 20000 ]; do
                    printf 'stdout-%s\\n' "$i"
                    printf 'stderr-%s\\n' "$i" >&2
                    i=$((i + 1))
                done
                """
            ],
            includeStandardErrorInSuccessfulOutput: true
        )

        let output = try await runner.run(request)

        XCTAssertTrue(output.contains("stdout-19999"))
        XCTAssertTrue(output.contains("stderr-19999"))
    }

    func testCancellationTerminatesRunningProcess() async throws {
        let runner = ProcessRunner()
        let task = Task {
            try await runner.run(
                ProcessRequest(
                    executable: "/bin/sh",
                    arguments: ["-c", "sleep 30"]
                )
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to fail the process request")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testTimeoutTerminatesRunningProcess() async throws {
        let runner = ProcessRunner()

        do {
            _ = try await runner.run(
                ProcessRequest(
                    executable: "/bin/sh",
                    arguments: ["-c", "sleep 30"],
                    timeout: .milliseconds(100)
                )
            )
            XCTFail("Expected the process request to time out")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testFastExitDrainsAllBytesExactlyOnce() async throws {
        let collector = StreamCollector()
        let output = try await ProcessRunner().run(ProcessRequest(
            executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ \"$i\" -lt 4096 ]; do printf '资料\\r'; printf 'error\\n' >&2; i=$((i + 1)); done"],
            includeStandardErrorInSuccessfulOutput: true,
            outputHandler: { data, stream in collector.append(data, stream: stream) }
        ))
        let stdout = String(repeating: "资料\r", count: 4096)
        let stderr = String(repeating: "error\n", count: 4096)
        XCTAssertEqual(output, stdout + stderr)
        XCTAssertEqual(collector.data(for: .standardOutput), Data(stdout.utf8))
        XCTAssertEqual(collector.data(for: .standardError), Data(stderr.utf8))
    }

    func testQuietDownloadStillCapturesErrorsWithoutPretendingToBeATerminal() async throws {
        let collector = StreamCollector()
        let output = try await ProcessRunner().run(ProcessRequest(
            executable: "/bin/sh",
            arguments: ["-c", "[ ! -t 1 ] && [ ! -t 2 ] || exit 9; printf discarded; printf 'get: Permission denied' >&2"],
            capturesOutput: false,
            includeStandardErrorInSuccessfulOutput: true,
            outputHandler: { data, stream in collector.append(data, stream: stream) }
        ))
        XCTAssertEqual(output, "get: Permission denied")
        XCTAssertEqual(collector.data(for: .standardOutput), Data())
        XCTAssertEqual(collector.data(for: .standardError), Data(output.utf8))
    }

    func testDownloadTaskIdentityAndLateProgressGuard() {
        let serverID = UUID()
        var task = DownloadTask(itemName: "x", remotePath: "/x", serverName: "Renamed", isDirectory: false, serverID: serverID)
        XCTAssertTrue(task.belongs(to: serverID))
        XCTAssertFalse(task.belongs(to: UUID()))
        XCTAssertFalse(task.belongs(to: nil))
        task.apply(DownloadProgress(bytesTransferred: 50, totalBytes: 100, speedBytesPerSecond: 10, estimatedRemainingSeconds: 5))
        XCTAssertEqual(task.progress, 0.5)
        task.finish(status: .completed)
        task.apply(DownloadProgress(bytesTransferred: 90, totalBytes: 100, speedBytesPerSecond: 10, estimatedRemainingSeconds: 1))
        XCTAssertEqual(task.progress, 1)
        XCTAssertNil(task.speedBytesPerSecond)
        XCTAssertNotNil(task.completedAt)
    }

    func testDownloadTaskComparesCapturedRemoteMetadata() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let task = DownloadTask(
            itemName: "report.pdf",
            remotePath: "/report.pdf",
            serverName: "server",
            isDirectory: false,
            remoteSize: 20,
            remoteModifiedAt: date
        )
        let current = RemoteItem(id: "/report.pdf", name: "report.pdf", path: "/report.pdf", kind: .file, size: 20, modifiedAt: date)
        let changed = RemoteItem(id: "/report.pdf", name: "report.pdf", path: "/report.pdf", kind: .file, size: 21, modifiedAt: date)

        XCTAssertEqual(task.remoteMetadataMatches(current), true)
        XCTAssertEqual(task.remoteMetadataMatches(changed), false)
    }

    func testDownloadTaskDecodesLegacyHistoryWithoutRemoteMetadata() throws {
        let task = DownloadTask(itemName: "legacy", remotePath: "/legacy", serverName: "server", isDirectory: false)
        let encoded = try JSONEncoder().encode(task)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "remoteSize")
        object.removeValue(forKey: "remoteModifiedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(DownloadTask.self, from: legacyData)
        XCTAssertNil(decoded.remoteSize)
        XCTAssertNil(decoded.remoteModifiedAt)
    }
    func testNewDownloadsHaveUnknownRatherThanFabricatedProgress() {
        for isDirectory in [false, true] {
            let task = DownloadTask(itemName: "test", remotePath: "/test", serverName: "test", isDirectory: isDirectory)
            XCTAssertNil(task.progress)
            XCTAssertNil(task.bytesTransferred)
            XCTAssertNil(task.totalBytes)
            XCTAssertNil(task.speedBytesPerSecond)
            XCTAssertNil(task.estimatedRemainingSeconds)
        }
    }

    func testQueuedDownloadOnlyAcceptsProgressAfterStarting() {
        let sample = DownloadProgress(
            bytesTransferred: 50,
            totalBytes: 100,
            speedBytesPerSecond: 10,
            estimatedRemainingSeconds: 5
        )
        var task = DownloadTask(
            itemName: "queued.zip",
            remotePath: "/queued.zip",
            serverName: "test",
            isDirectory: false,
            status: .queued
        )

        task.apply(sample)
        XCTAssertNil(task.progress)
        task.start()
        XCTAssertEqual(task.status, .downloading)
        task.apply(sample)
        XCTAssertEqual(task.progress, 0.5)
        task.finish(status: .completed)
        XCTAssertEqual(task.status, .completed)
        XCTAssertEqual(task.progress, 1)

        var cancelled = DownloadTask(
            itemName: "cancelled.zip",
            remotePath: "/cancelled.zip",
            serverName: "test",
            isDirectory: false,
            status: .queued
        )
        cancelled.finish(status: .cancelled)
        XCTAssertEqual(cancelled.status, .cancelled)
    }

    func testRemoteFileTypesUseDistinctIcons() {
        let expectedIcons = [
            "photo.jpg": "photo",
            "movie.mp4": "film",
            "audio.flac": "waveform",
            "manual.pdf": "doc.richtext",
            "backup.tar": "archivebox",
            "main.swift": "chevron.left.forwardslash.chevron.right",
            "notes.md": "doc.text",
            "budget.xlsx": "tablecells",
            "slides.key": "rectangle.on.rectangle",
            "installer.dmg": "externaldrive",
            "unknown.bin": "doc"
        ]

        for (name, icon) in expectedIcons {
            let item = RemoteItem(id: name, name: name, path: "/\(name)", kind: .file, size: nil, modifiedAt: nil)
            XCTAssertEqual(item.systemImageName, icon, "Unexpected icon for \(name)")
        }
    }

    func testCompactFileSizesUseConsistentUnitSymbols() {
        let chinese = Locale(identifier: "zh-CN")
        XCTAssertEqual(CompactFileSizeFormatter.string(fromByteCount: 7, locale: chinese), "7 B")
        XCTAssertEqual(CompactFileSizeFormatter.string(fromByteCount: 7_000, locale: chinese), "7 KB")
        XCTAssertEqual(CompactFileSizeFormatter.string(fromByteCount: 7_500_000, locale: chinese), "7.5 MB")
    }

    func testRetryIdentityDoesNotUseDisplayNameOrMissingIdentity() {
        let serverID = UUID()
        let original = DownloadTask(itemName: "x", remotePath: "/x", serverName: "Same name", isDirectory: false, serverID: serverID)
        let other = DownloadTask(itemName: "x", remotePath: "/x", serverName: "Same name", isDirectory: false, serverID: UUID())
        let renamed = DownloadTask(itemName: "x", remotePath: "/x", serverName: "New name", isDirectory: false, serverID: serverID)
        let unknown = DownloadTask(itemName: "x", remotePath: "/x", serverName: "Same name", isDirectory: false)
        XCTAssertFalse(original.belongs(to: other.serverID))
        XCTAssertTrue(original.belongs(to: renamed.serverID))
        XCTAssertFalse(unknown.belongs(to: nil))
        XCTAssertNotEqual(original.id, renamed.id)
    }

    func testTerminalTasksKeepBytesButRejectLateSamples() {
        for status in [DownloadTask.Status.cancelled, .failed("offline")] {
            var task = DownloadTask(itemName: "x", remotePath: "/x", serverName: "s", isDirectory: false)
            task.apply(DownloadProgress(bytesTransferred: 50, totalBytes: 100, speedBytesPerSecond: 10, estimatedRemainingSeconds: 5))
            task.finish(status: status)
            let finished = task
            task.apply(DownloadProgress(bytesTransferred: 100, totalBytes: 100, speedBytesPerSecond: 20, estimatedRemainingSeconds: 0))
            XCTAssertEqual(task, finished)
            XCTAssertEqual(task.bytesTransferred, 50)
            XCTAssertEqual(task.progress, 0.5)
            XCTAssertNil(task.speedBytesPerSecond)
            XCTAssertNil(task.estimatedRemainingSeconds)
        }
    }

    func testSamplerProducesRenderableMetricsAndInvalidatesStaleTotal() {
        var sampler = DownloadProgressSampler(totalBytes: 100, now: 0)
        let half = sampler.sample(bytes: 50, now: 2)
        XCTAssertEqual(half.fraction, 0.5)
        XCTAssertEqual(half.speedBytesPerSecond, 25)
        XCTAssertEqual(half.estimatedRemainingSeconds, 2)
        XCTAssertLessThan(sampler.sample(bytes: 100, now: 4).fraction ?? 1, 1)
        XCTAssertNil(sampler.sample(bytes: 101, now: 5).totalBytes)
        let truncated = sampler.sample(bytes: 1, now: 6)
        XCTAssertNil(truncated.speedBytesPerSecond)
        XCTAssertNil(truncated.fraction)
        var unknown = DownloadProgressSampler(totalBytes: nil, now: 0)
        XCTAssertNil(unknown.sample(bytes: 10, now: 1).fraction)
        var empty = DownloadProgressSampler(totalBytes: 0, now: 0)
        XCTAssertNil(empty.sample(bytes: 0, now: 1).fraction)
    }

    private struct FailingRunner: ProcessRunning {
        func run(_ request: ProcessRequest) async throws -> String {
            throw ProcessRunnerError.failed("spawn ssh\r\nPermission denied (publickey).\r\n")
        }
    }

    func testControlConnectionFailureIsNotSilentlyIgnored() async throws {
        let profile = ServerProfile(host: "example.invalid", username: "test")
        let client = SFTPClient(profile: profile, processRunner: FailingRunner())

        do {
            try await client.startControlConnection(for: profile)
            XCTFail("Expected control connection failure")
        } catch let error as SFTPClientError {
            guard case .processFailed(let message) = error else {
                return XCTFail("Unexpected client error: \(error)")
            }
            XCTAssertEqual(message, AppLanguage.text("error.authenticationRejected"))
        }
    }

    func testControlConnectionUsesOpenSSHTrustOnFirstUse() async throws {
        let profile = ServerProfile(host: "example.invalid", username: "test")
        let runner = ListingRunner(output: "")
        let client = SFTPClient(profile: profile, processRunner: runner)

        try await client.startControlConnection(for: profile)

        let requests = await runner.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertTrue(request.arguments.contains("StrictHostKeyChecking=accept-new"))
        XCTAssertTrue(request.arguments.contains("ControlMaster=yes"))
    }

    func testConnectStartsAuthenticationWithoutSeparateKeyscan() async throws {
        let profile = ServerProfile(host: "example.invalid", username: "test")
        let runner = ListingRunner(output: "")
        let client = SFTPClient(processRunner: runner)

        try await client.connect(profile: profile)

        let requests = await runner.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.executable, "/usr/bin/ssh")
        XCTAssertFalse(requests.contains { $0.executable == "/usr/bin/ssh-keyscan" })
    }

    func testClientCleansProcessFailureMessage() async throws {
        let client = SFTPClient(processRunner: FailingRunner())
        do {
            try await client.connect(profile: ServerProfile(host: "example.invalid", username: "test"))
            XCTFail("Expected the injected process failure")
        } catch let error as SFTPClientError {
            guard case .processFailed(let message) = error else {
                return XCTFail("Unexpected client error: \(error)")
            }
            XCTAssertEqual(message, AppLanguage.text("error.authenticationRejected"))
        }
    }

    func testDirectoryListingIncludesHiddenAndSpecialFileTypes() async throws {
        let runner = ListingRunner()
        let client = SFTPClient(
            profile: ServerProfile(host: "example.invalid", username: "test"),
            processRunner: runner
        )

        let items = try await client.listDirectory(".")

        XCTAssertEqual(items.map(\.name), ["Documents", ".env", "current", "events.pipe"])
        XCTAssertEqual(items.map(\.kind), [RemoteItem.Kind.directory, .file, .symlink, .unknown])
        let recordedInput = await runner.latestInput
        let latestInput = try XCTUnwrap(recordedInput)
        XCTAssertTrue(latestInput.contains("ls -lan \".\""))
    }

    func testDirectoryListingDoesNotDropLocalizedDatesOrUnknownTypes() async throws {
        let runner = ListingRunner(output: """
        -rw-r--r-- 1 0 0 12 9月 14 12:00 localized.txt
        ?--------- 1 0 0 0 9月 14 12:01 device.entry
        srwxr-xr-x 1 0 0 0 9月 14 12:02 service.sock
        """)
        let client = SFTPClient(
            profile: ServerProfile(host: "example.invalid", username: "test"),
            processRunner: runner
        )

        let items = try await client.listDirectory(".")

        XCTAssertEqual(items.map(\.name), ["device.entry", "localized.txt", "service.sock"])
        XCTAssertEqual(items.map(\.kind), [.unknown, .file, .unknown])
    }

    func testDirectoryListingAcceptsUnknownLinkCountsFromSFTPServer() async throws {
        let runner = ListingRunner(output: """
        dr-xr-x---    ? 0        0            4096 Sep  3 11:42 root
        -rw-r--r--    ? 0        0             220 Apr 23  2023 .profile
        lrwxrwxrwx    ? 0        0               7 Sep  3 11:42 bin -> usr/bin
        """)
        let client = SFTPClient(
            profile: ServerProfile(host: "example.invalid", username: "root"),
            processRunner: runner
        )

        let items = try await client.listDirectory(".")

        XCTAssertEqual(items.map(\.name), ["root", ".profile", "bin"])
        XCTAssertEqual(items.map(\.kind), [.directory, .file, .symlink])
    }

    func testDirectoryListingCachesNavigationButRefreshBypassesCache() async throws {
        let runner = ListingRunner()
        let client = SFTPClient(
            profile: ServerProfile(host: "example.invalid", username: "test"),
            processRunner: runner
        )

        _ = try await client.listDirectory("/Documents")
        _ = try await client.listDirectory("/Documents")
        let cachedCount = await runner.count
        XCTAssertEqual(cachedCount, 1)

        _ = try await client.listDirectory("/Documents", useCache: false)
        let refreshedCount = await runner.count
        XCTAssertEqual(refreshedCount, 2)
    }

    func testFailureIncludesStandardError() async throws {
        let runner = ProcessRunner()

        do {
            _ = try await runner.run(
                ProcessRequest(
                    executable: "/bin/sh",
                    arguments: ["-c", "printf 'expected failure' >&2; exit 7"]
                )
            )
            XCTFail("Expected the process request to fail")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .failed("expected failure"))
        }
    }
}

@MainActor
final class WorkspaceSessionTests: XCTestCase {
    private func task() -> DownloadTask {
        DownloadTask(itemName: "Documents", remotePath: "/Documents", serverName: "fixture",
                     isDirectory: true, serverID: UUID())
    }

    func testNavigationPreservesBrowsingAndCancelsOnlySpatialFeedback() throws {
        let session = WorkspaceSession()
        session.searchText = "Documents"
        session.itemFilter = .folders
        session.updateFrames([
            "file:/Documents": CGRect(x: 100, y: 100, width: 20, height: 20),
            "browser": CGRect(x: 80, y: 80, width: 500, height: 400),
            "destination": CGRect(x: 20, y: 60, width: 18, height: 18)
        ])
        session.acknowledgeDownload(task(), reduceMotion: false, fromKeyboard: false)
        XCTAssertNotNil(session.downloadFlight)
        XCTAssertEqual(session.workspace, .servers, "Accepting a download must not navigate")
        for workspace in [Workspace.tasks, .settings, .servers] {
            session.navigate(to: workspace)
            XCTAssertEqual(session.workspace, workspace)
            XCTAssertEqual(session.searchText, "Documents")
            XCTAssertEqual(session.itemFilter, .folders)
            XCTAssertNil(session.downloadFlight, "A flight must not continue over another workspace")
            XCTAssertTrue(session.downloadAcknowledged)
        }
    }

    func testNavigationRestoresBrowseContextOnReturn() throws {
        let session = WorkspaceSession()
        session.searchText = "FilteredSearch"
        session.itemFilter = .files
        // Simulate being away from servers, then navigating back.
        session.navigate(to: .tasks)
        XCTAssertEqual(session.searchText, "FilteredSearch")
        XCTAssertEqual(session.itemFilter, .files)
        // Returning to servers restores what was saved before leaving.
        session.navigate(to: .servers)
        XCTAssertEqual(session.searchText, "FilteredSearch")
        XCTAssertEqual(session.itemFilter, .files)
    }

    func testEarlierFeedbackCannotDismissANewerAcknowledgement() throws {
        let session = WorkspaceSession()
        session.acknowledgeDownload(task(), reduceMotion: true, fromKeyboard: false)
        let earlier = try XCTUnwrap(session.feedbackID)
        session.acknowledgeDownload(task(), reduceMotion: false, fromKeyboard: true)
        let latest = try XCTUnwrap(session.feedbackID)
        session.finishFeedback(earlier)
        XCTAssertTrue(session.downloadAcknowledged)
        XCTAssertEqual(session.feedbackID, latest)
        session.finishFeedback(latest)
        XCTAssertFalse(session.downloadAcknowledged)
        XCTAssertNil(session.feedbackID)
    }

    func testNonSpatialFeedbackForKeyboardReducedMotionAndOtherWorkspaces() {
        let session = WorkspaceSession()
        session.updateFrames([
            "file:/Documents": CGRect(x: 100, y: 100, width: 20, height: 20),
            "browser": CGRect(x: 80, y: 80, width: 500, height: 400),
            "destination": CGRect(x: 20, y: 60, width: 18, height: 18)
        ])
        for (workspace, reduced, keyboard) in [(Workspace.servers, true, false), (.servers, false, true), (.tasks, false, false)] {
            session.navigate(to: workspace)
            session.acknowledgeDownload(task(), reduceMotion: reduced, fromKeyboard: keyboard)
            XCTAssertTrue(session.downloadAcknowledged)
            XCTAssertNil(session.downloadFlight)
            XCTAssertEqual(session.workspace, workspace)
        }
    }



}

final class PreviewTextLoaderTests: XCTestCase {
    private func withFile(_ data: Data, extension ext: String = "log", check: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preview." + ext)
        try data.write(to: url)
        try check(url)
    }

    func testLogWithoutQuickLookPluginReturnsContents() throws {
        let text = "启动完成\n{\"status\": \"ready\"}\n"
        try withFile(Data(text.utf8)) { XCTAssertEqual(PreviewTextLoader.load($0), text) }
    }

    func testBinaryNeverAppearsAsGarbledText() throws {
        try withFile(Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff])) { XCTAssertNil(PreviewTextLoader.load($0)) }
    }

    func testLargeUTF8LogClipsOnlyAtValidCharacterBoundary() throws {
        let content = String(repeating: "桥", count: PreviewTextLoader.limit / 3 + 10)
        try withFile(Data(content.utf8)) { url in
            let text = try XCTUnwrap(PreviewTextLoader.load(url))
            XCTAssertLessThanOrEqual(text.utf8.count, PreviewTextLoader.limit)
            XCTAssertFalse(text.contains("�"))
            XCTAssertTrue(content.hasPrefix(text))
        }
    }
}

extension PreviewTextLoaderTests {
    func testPDFUsesNativePreviewEvenWhenContentsAreASCII() throws {
        try withFile(Data("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF".utf8), extension: "pdf") {
            XCTAssertNil(PreviewTextLoader.load($0))
        }
    }
}

@MainActor
final class ServerNavigationTests: XCTestCase {
    private final class MemoryCredentials: ServerPasswordStoring, @unchecked Sendable {
        var values: [UUID: String] = [:]
        func readPassword(serverID: UUID) throws -> String? { values[serverID] }
        func setPassword(_ password: String, serverID: UUID) throws { values[serverID] = password }
        func deletePassword(serverID: UUID) throws { values.removeValue(forKey: serverID) }
    }

    func testLegacyPasswordMigratesToKeychainAndIsRemovedFromDefaults() throws {
        let suite = "CloudBridgeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = SavedServer(host: "example.invalid", username: "root")
        var legacyRecord = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(server)) as? [String: Any]
        )
        legacyRecord["password"] = "legacy-secret"
        defaults.set(
            try JSONSerialization.data(withJSONObject: [legacyRecord]),
            forKey: SavedServerStore.storageKey
        )
        let credentials = MemoryCredentials()

        let migrated = SavedServerStore.load(defaults: defaults, credentials: credentials)

        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated[0].password, "")
        XCTAssertEqual(try credentials.readPassword(serverID: server.id), "legacy-secret")
        let persisted = try XCTUnwrap(defaults.data(forKey: SavedServerStore.storageKey))
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("legacy-secret"))
    }

    func testSavedServerRoundTripDoesNotPersistPassword() throws {
        let server = SavedServer(host: "example.invalid", username: "root", password: "local-secret")

        let data = try JSONEncoder().encode(server)
        let restored = try JSONDecoder().decode(SavedServer.self, from: data)

        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("local-secret"))
        XCTAssertEqual(restored.password, "")
    }

    func testSelectingAndEditingServerUsesKeychainPasswordWithoutExposingIt() throws {
        let server = SavedServer(host: "example.invalid", username: "root")
        let credentials = MemoryCredentials()
        try credentials.setPassword("local-secret", serverID: server.id)
        let model = BrowserModel(initialServers: [server], credentials: credentials)

        XCTAssertEqual(model.profile.password, "local-secret")
        model.editSelectedServer()
        XCTAssertEqual(model.editingPassword, "")
        XCTAssertTrue(model.hasSavedPassword(for: server))
    }

    func testReconnectRestoresPasswordFromKeychain() throws {
        let server = SavedServer(host: "example.invalid", username: "root")
        let credentials = MemoryCredentials()
        try credentials.setPassword("local-secret", serverID: server.id)
        let model = BrowserModel(initialServers: [server], credentials: credentials)
        model.profile.password = ""

        let reconnectProfile = model.preparedProfileForConnection()

        XCTAssertEqual(reconnectProfile.password, "local-secret")
        XCTAssertEqual(reconnectProfile.host, server.host)
        XCTAssertEqual(reconnectProfile.username, server.username)
    }

    func testNewServerUsesEditableConnectionDefaults() {
        let model = BrowserModel(initialServers: [])

        model.newServer()

        XCTAssertEqual(model.editingServer.username, "root")
        XCTAssertTrue(model.editingServer.host.hasPrefix("192.168.1."))
        let finalOctet = Int(model.editingServer.host.split(separator: ".").last ?? "")
        XCTAssertTrue((2...254).contains(finalOctet ?? 0))
    }

    func testAddingWhileConnectedKeepsCurrentBrowseContext() {
        let server = SavedServer(host: "example.invalid", username: "test")
        let model = BrowserModel(initialServers: [server])
        model.isConnected = true
        model.currentPath = "/documents"
        model.newServer()
        XCTAssertTrue(model.isShowingServerEditor)
        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(model.selectedServerID, server.id)
        XCTAssertEqual(model.currentPath, "/documents")
        XCTAssertNotEqual(model.editingServer.id, server.id)
    }

    func testSwitchCannotInterruptDownloadOrSelectUnknownServer() {
        let first = SavedServer(host: "first.invalid", username: "test")
        let second = SavedServer(host: "second.invalid", username: "test")
        let model = BrowserModel(initialServers: [first, second])
        model.isConnected = true
        model.isDownloading = true
        model.switchServer(to: second.id)
        XCTAssertEqual(model.selectedServerID, first.id)
        XCTAssertTrue(model.isConnected)
        XCTAssertTrue(model.isDownloading)
        model.isDownloading = false
        model.switchServer(to: UUID())
        XCTAssertEqual(model.selectedServerID, first.id)
        XCTAssertFalse(model.isBusy)
    }

    func testSelectedItemsFollowVisibleTableOrderAndExcludeParent() {
        let model = BrowserModel(initialServers: [])
        let second = RemoteItem(id: "second", name: "second.txt", path: "/second.txt", kind: .file, size: nil, modifiedAt: nil)
        let first = RemoteItem(id: "first", name: "first.txt", path: "/first.txt", kind: .file, size: nil, modifiedAt: nil)
        model.items = [.parent, second, first]
        model.selectedItemIDs = [first.id, RemoteItem.parent.id, second.id]

        XCTAssertEqual(model.selectedItems.map(\.id), [second.id, first.id])
        XCTAssertNil(model.selectedItem)
        XCTAssertNil(model.selectedItemID)
    }

    func testActiveDownloadCountIncludesQueuedDownloadingAndPaused() {
        let model = BrowserModel(initialServers: [])
        model.downloadTasks = [
            DownloadTask(itemName: "queued", remotePath: "/queued", serverName: "test", isDirectory: false, status: .queued),
            DownloadTask(itemName: "active", remotePath: "/active", serverName: "test", isDirectory: false),
            DownloadTask(itemName: "paused", remotePath: "/paused", serverName: "test", isDirectory: false),
            DownloadTask(itemName: "done", remotePath: "/done", serverName: "test", isDirectory: false, status: .queued)
        ]
        model.downloadTasks[2].pause()
        model.downloadTasks[3].start()
        model.downloadTasks[3].finish(status: .completed)

        XCTAssertEqual(model.activeDownloadCount, 3)
    }

    func testCancellingQueuedDownloadOnlyCancelsChosenTask() {
        let model = BrowserModel(initialServers: [])
        let active = DownloadTask(itemName: "active", remotePath: "/active", serverName: "test", isDirectory: false)
        let queued = DownloadTask(itemName: "queued", remotePath: "/queued", serverName: "test", isDirectory: false, status: .queued)
        model.downloadTasks = [active, queued]

        model.cancelDownload(queued)

        XCTAssertEqual(model.downloadTasks[0].status, .downloading)
        XCTAssertEqual(model.downloadTasks[1].status, .cancelled)
    }

    func testDownloadTaskCanPauseAndResumeWithoutLosingProgress() {
        var task = DownloadTask(itemName: "archive", remotePath: "/archive", serverName: "test", isDirectory: false)
        task.apply(DownloadProgress(bytesTransferred: 25, totalBytes: 100, speedBytesPerSecond: 10, estimatedRemainingSeconds: 7.5))

        task.pause()
        XCTAssertEqual(task.status, .paused)
        XCTAssertEqual(task.progress, 0.25)
        XCTAssertNil(task.speedBytesPerSecond)
        XCTAssertNil(task.estimatedRemainingSeconds)

        task.resume()
        XCTAssertEqual(task.status, .downloading)
        XCTAssertEqual(task.progress, 0.25)
    }

    func testRetryQueuesOnOriginalServerWhileAnotherDownloadIsActive() {
        let server = SavedServer(host: "example.invalid", username: "root", password: "secret")
        var cancelled = DownloadTask(
            itemName: "archive.zip",
            remotePath: "/archive.zip",
            serverName: server.displayName,
            isDirectory: false,
            serverID: server.id,
            remoteSize: 128,
            status: .downloading
        )
        cancelled.apply(DownloadProgress(bytesTransferred: 64, totalBytes: 128, speedBytesPerSecond: 10, estimatedRemainingSeconds: 6.4))
        cancelled.finish(status: .cancelled)
        let originalTaskID = cancelled.id
        let model = BrowserModel(initialServers: [server], initialDownloadTasks: [cancelled])
        model.isConnected = true
        model.isDownloading = true

        XCTAssertTrue(model.canRetry(cancelled))
        model.retry(cancelled)

        XCTAssertEqual(model.downloadTasks.count, 1)
        XCTAssertEqual(model.downloadTasks[0].id, originalTaskID)
        XCTAssertEqual(model.downloadTasks[0].status, .queued)
        XCTAssertNil(model.downloadTasks[0].progress)
        XCTAssertNil(model.downloadTasks[0].bytesTransferred)
        XCTAssertNil(model.downloadTasks[0].completedAt)
    }

    func testClearDownloadHistoryPreservesActiveQueue() {
        let model = BrowserModel(initialServers: [])
        model.downloadTasks = [
            DownloadTask(itemName: "queued", remotePath: "/queued", serverName: "test", isDirectory: false, status: .queued),
            DownloadTask(itemName: "failed", remotePath: "/failed", serverName: "test", isDirectory: false),
            DownloadTask(itemName: "cancelled", remotePath: "/cancelled", serverName: "test", isDirectory: false)
        ]
        model.downloadTasks[1].finish(status: .failed("offline"))
        model.downloadTasks[2].finish(status: .cancelled)

        XCTAssertTrue(model.hasDownloadHistory)
        model.clearDownloadHistory()

        XCTAssertEqual(model.downloadTasks.map(\.itemName), ["queued"])
        XCTAssertFalse(model.hasDownloadHistory)
    }

    func testRemoveDownloadRecordOnlyRemovesTerminalTask() {
        let model = BrowserModel(initialServers: [])
        let active = DownloadTask(itemName: "active", remotePath: "/active", serverName: "test", isDirectory: false)
        var cancelled = DownloadTask(itemName: "cancelled", remotePath: "/cancelled", serverName: "test", isDirectory: false)
        cancelled.finish(status: .cancelled)
        model.downloadTasks = [active, cancelled]

        model.removeDownloadRecord(active)
        XCTAssertEqual(model.downloadTasks.map(\.itemName), ["active", "cancelled"])

        model.removeDownloadRecord(cancelled)
        XCTAssertEqual(model.downloadTasks.map(\.itemName), ["active"])
    }

    func testDownloadsCanBeQueuedWhileAnotherDownloadIsActive() {
        let server = SavedServer(host: "example.invalid", username: "root", password: "secret")
        let model = BrowserModel(initialServers: [server])
        model.isConnected = true
        model.isDownloading = true
        let first = RemoteItem(id: "/first.txt", name: "first.txt", path: "/first.txt", kind: .file, size: 10, modifiedAt: nil)
        let second = RemoteItem(id: "/second.txt", name: "second.txt", path: "/second.txt", kind: .file, size: 20, modifiedAt: nil)

        model.download([first, second])

        XCTAssertEqual(model.downloadTasks.map(\.itemName), ["first.txt", "second.txt"])
        XCTAssertEqual(model.downloadTasks.map(\.status), [.queued, .queued])
    }

    func testExistingDownloadQueuesWithoutConfirmation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("existing".utf8).write(to: directory.appendingPathComponent("report.pdf"))

        let server = SavedServer(host: "example.invalid", username: "root", password: "secret")
        let model = BrowserModel(initialServers: [server])
        model.localDownloadDirectory = directory
        model.isConnected = true
        model.isDownloading = true
        let item = RemoteItem(id: "/report.pdf", name: "report.pdf", path: "/report.pdf", kind: .file, size: 8, modifiedAt: nil)

        model.download(item)

        XCTAssertEqual(model.downloadTasks.map(\.itemName), ["report.pdf"])
        XCTAssertEqual(model.downloadTasks.map(\.status), [.queued])
    }

    func testHiddenRemoteNamesUseVisibleLocalNamesAndRecognizeLegacyDownloads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let server = SavedServer(host: "example.invalid", username: "root", password: "secret")
        let model = BrowserModel(initialServers: [server])
        model.localDownloadDirectory = directory
        let item = RemoteItem(id: "/.env", name: ".env", path: "/.env", kind: .file, size: 8, modifiedAt: nil)

        XCTAssertEqual(item.localDownloadName, "_.env")
        try Data("legacy".utf8).write(to: directory.appendingPathComponent(".env"))
        XCTAssertEqual(model.existingLocalDownload(for: item)?.lastPathComponent, ".env")

        try FileManager.default.removeItem(at: directory.appendingPathComponent(".env"))
        try Data("visible".utf8).write(to: directory.appendingPathComponent("_.env"))
        XCTAssertEqual(model.existingLocalDownload(for: item)?.lastPathComponent, "_.env")
    }

    func testCompletedDownloadHistoryPersistsButActiveTasksDoNot() throws {
        let suiteName = "CloudBridgeTests.DownloadHistory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let serverID = UUID()
        var completed = DownloadTask(itemName: "done.zip", remotePath: "/done.zip", serverName: "server", isDirectory: false, serverID: serverID)
        completed.finish(status: .completed, destination: URL(filePath: "/tmp/done.zip"))
        let queued = DownloadTask(itemName: "queued.zip", remotePath: "/queued.zip", serverName: "server", isDirectory: false, serverID: serverID, status: .queued)

        DownloadHistoryStore.save([completed, queued], defaults: defaults)
        let restored = DownloadHistoryStore.load(defaults: defaults)

        XCTAssertEqual(restored, [completed])
    }

    func testFailedAndCancelledHistoryPersistForRetry() throws {
        let suiteName = "CloudBridgeTests.DownloadHistory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let serverID = UUID()
        var failed = DownloadTask(itemName: "failed.zip", remotePath: "/failed.zip", serverName: "server", isDirectory: false, serverID: serverID)
        failed.finish(status: .failed("offline"))
        var cancelled = DownloadTask(itemName: "cancelled.zip", remotePath: "/cancelled.zip", serverName: "server", isDirectory: false, serverID: serverID)
        cancelled.finish(status: .cancelled)
        let paused = DownloadTask(itemName: "paused.zip", remotePath: "/paused.zip", serverName: "server", isDirectory: false, serverID: serverID, status: .paused)

        DownloadHistoryStore.save([failed, cancelled, paused], defaults: defaults)
        let restored = DownloadHistoryStore.load(defaults: defaults)

        XCTAssertEqual(restored.map(\.status), [.failed("offline"), .cancelled])
        XCTAssertEqual(restored.compactMap(\.completedAt).count, 2)
    }

    func testCompletedServerHistoryDoesNotBlockAnotherDownload() {
        let server = SavedServer(host: "example.invalid", username: "root", password: "secret")
        var completed = DownloadTask(itemName: "archive.zip", remotePath: "/archive.zip", serverName: server.displayName, isDirectory: false, serverID: server.id)
        completed.finish(status: .completed, destination: URL(filePath: "/tmp/archive.zip"))
        let model = BrowserModel(initialServers: [server], initialDownloadTasks: [completed])
        model.isConnected = true
        model.isDownloading = true
        let item = RemoteItem(id: "/archive.zip", name: "archive.zip", path: "/archive.zip", kind: .file, size: 8, modifiedAt: nil)

        model.download(item)

        XCTAssertEqual(model.downloadTasks.map(\.itemName), ["archive.zip", "archive.zip"])
        XCTAssertEqual(model.downloadTasks.first?.status, .queued)
        XCTAssertEqual(model.downloadTasks.last?.status, .completed)
    }

    func testRemoteFileFindsItsCompletedHistoryRecord() {
        let server = SavedServer(host: "example.invalid", username: "root", password: "secret")
        var completed = DownloadTask(itemName: "archive.zip", remotePath: "/archive.zip", serverName: server.displayName, isDirectory: false, serverID: server.id)
        completed.finish(status: .completed, destination: URL(filePath: "/tmp/archive.zip"))
        let model = BrowserModel(initialServers: [server], initialDownloadTasks: [completed])
        let matching = RemoteItem(id: "/archive.zip", name: "archive.zip", path: "/archive.zip", kind: .file, size: 8, modifiedAt: nil)
        let other = RemoteItem(id: "/other.zip", name: "other.zip", path: "/other.zip", kind: .file, size: 8, modifiedAt: nil)

        XCTAssertEqual(model.completedDownload(for: matching)?.id, completed.id)
        XCTAssertNil(model.completedDownload(for: other))
    }

    func testLocalFileStatusDistinguishesCurrentChangedAndMissingCopies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.pdf")
        try Data(repeating: 1, count: 20).write(to: destination)

        let server = SavedServer(host: "example.invalid", username: "root", password: "secret")
        var task = DownloadTask(
            itemName: "report.pdf",
            remotePath: "/report.pdf",
            serverName: server.displayName,
            isDirectory: false,
            serverID: server.id,
            remoteSize: 20
        )
        task.finish(status: .completed, destination: destination)
        let model = BrowserModel(initialServers: [server], initialDownloadTasks: [task])
        model.localDownloadDirectory = directory
        let current = RemoteItem(id: "/report.pdf", name: "report.pdf", path: "/report.pdf", kind: .file, size: 20, modifiedAt: nil)
        let changed = RemoteItem(id: "/report.pdf", name: "report.pdf", path: "/report.pdf", kind: .file, size: 21, modifiedAt: nil)

        XCTAssertEqual(model.localFileStatus(for: current), .current)
        XCTAssertEqual(model.localFileStatus(for: changed), .remoteUpdated)
        try FileManager.default.removeItem(at: destination)
        XCTAssertEqual(model.localFileStatus(for: current), .missing)
    }
}

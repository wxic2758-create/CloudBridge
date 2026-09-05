import Foundation

enum ProcessOutputStream: Sendable, Equatable {
    case standardOutput
    case standardError
}

struct ProcessRequest: Sendable {
    let executable: String
    let arguments: [String]
    let capturesOutput: Bool
    let standardInputData: Data?
    let environment: [String: String]?
    let includeStandardErrorInSuccessfulOutput: Bool
    let currentDirectoryURL: URL?
    let timeout: Duration?
    let outputHandler: (@Sendable (Data, ProcessOutputStream) -> Void)?

    init(
        executable: String,
        arguments: [String] = [],
        capturesOutput: Bool = true,
        standardInputData: Data? = nil,
        environment: [String: String]? = nil,
        includeStandardErrorInSuccessfulOutput: Bool = false,
        currentDirectoryURL: URL? = nil,
        timeout: Duration? = nil,
        outputHandler: (@Sendable (Data, ProcessOutputStream) -> Void)? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.capturesOutput = capturesOutput
        self.standardInputData = standardInputData
        self.environment = environment
        self.includeStandardErrorInSuccessfulOutput = includeStandardErrorInSuccessfulOutput
        self.currentDirectoryURL = currentDirectoryURL
        self.timeout = timeout
        self.outputHandler = outputHandler
    }
}

protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> String
}

enum ProcessRunnerError: LocalizedError, Equatable {
    case cancelled
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "The server command was cancelled."
        case .timedOut:
            "The server command timed out."
        case let .failed(message):
            message.isEmpty ? "The process failed." : message
        }
    }
}

final class ProcessRunner: ProcessRunning, @unchecked Sendable {
    func run(_ request: ProcessRequest) async throws -> String {
        let holder = ExecutionHolder()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
                let execution = ProcessExecution(request: request, continuation: continuation)
                holder.set(execution)
                execution.start()
            }
        }, onCancel: {
            holder.cancel()
        })
    }
}

private final class ExecutionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var execution: ProcessExecution?
    private var cancellationRequested = false

    func set(_ execution: ProcessExecution) {
        lock.lock()
        self.execution = execution
        let shouldCancel = cancellationRequested
        lock.unlock()

        if shouldCancel {
            execution.cancel(with: .cancelled)
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let execution = self.execution
        lock.unlock()

        execution?.cancel(with: .cancelled)
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let request: ProcessRequest
    private let continuation: CheckedContinuation<String, any Error>
    private let lock = NSLock()
    private var process: Process?
    private var didFinish = false
    private var terminationError: (any Error)?
    private var stdoutTask: Task<Data, Never>?
    private var stderrTask: Task<Data, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        request: ProcessRequest,
        continuation: CheckedContinuation<String, any Error>
    ) {
        self.request = request
        self.continuation = continuation
    }

    func start() {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        lock.lock()
        guard didFinish == false else {
            lock.unlock()
            return
        }
        lock.unlock()

        process.executableURL = URL(filePath: request.executable)
        process.arguments = request.arguments
        process.currentDirectoryURL = request.currentDirectoryURL
        process.standardInput = request.standardInputData == nil ? FileHandle.nullDevice : stdinPipe
        process.standardOutput = request.capturesOutput ? stdoutPipe : FileHandle.nullDevice
        process.standardError = stderrPipe
        if let environment = request.environment {
            process.environment = environment
        }

        let capturesOutput = request.capturesOutput
        let stdoutTask = Task.detached {
            capturesOutput
                ? stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                : Data()
        }
        let stderrTask = Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        lock.lock()
        self.process = process
        self.stdoutTask = stdoutTask
        self.stderrTask = stderrTask
        lock.unlock()

        process.terminationHandler = { [weak self] process in
            Task.detached {
                let stdout = await stdoutTask.value
                let stderr = await stderrTask.value
                self?.finish(
                    terminationStatus: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
            }
        }

        do {
            try process.run()
            lock.lock()
            let shouldTerminate = didFinish
            lock.unlock()
            if shouldTerminate {
                process.terminate()
                return
            }
            if let standardInputData = request.standardInputData {
                stdinPipe.fileHandleForWriting.write(standardInputData)
                try stdinPipe.fileHandleForWriting.close()
            }
            if let timeout = request.timeout {
                timeoutTask = Task.detached { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        self?.cancel(with: .timedOut)
                    } catch {
                        // The process finished or was cancelled before the timeout.
                    }
                }
            }
        } catch {
            finish(error: error, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        }
    }

    func cancel(with error: ProcessRunnerError) {
        lock.lock()
        guard didFinish == false else {
            lock.unlock()
            return
        }
        terminationError = error
        let process = self.process
        lock.unlock()

        if let process, process.isRunning {
            process.terminate()
        } else {
            finish(error: error)
        }
    }

    private func finish(
        terminationStatus: Int32? = nil,
        stdout: Data = Data(),
        stderr: Data = Data(),
        error: (any Error)? = nil,
        stdoutPipe: Pipe? = nil,
        stderrPipe: Pipe? = nil
    ) {
        let finalError: (any Error)?
        let shouldResume: Bool

        lock.lock()
        shouldResume = didFinish == false
        if shouldResume {
            didFinish = true
            finalError = terminationError ?? error
        } else {
            finalError = nil
        }
        let timeoutTask = self.timeoutTask
        let stdoutTask = self.stdoutTask
        let stderrTask = self.stderrTask
        lock.unlock()

        guard shouldResume else {
            return
        }

        if stdout.isEmpty == false {
            request.outputHandler?(stdout, .standardOutput)
        }
        if stderr.isEmpty == false {
            request.outputHandler?(stderr, .standardError)
        }

        timeoutTask?.cancel()
        if let stdoutPipe {
            try? stdoutPipe.fileHandleForReading.close()
        }
        if let stderrPipe {
            try? stderrPipe.fileHandleForReading.close()
        }
        stdoutTask?.cancel()
        stderrTask?.cancel()

        if let finalError {
            continuation.resume(throwing: finalError)
            return
        }

        guard terminationStatus == 0 else {
            continuation.resume(
                throwing: ProcessRunnerError.failed(
                    String(data: stderr + stdout, encoding: .utf8) ?? ""
                )
            )
            return
        }

        let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
        let stderrText = String(data: stderr, encoding: .utf8) ?? ""
        continuation.resume(
            returning: stdoutText + (request.includeStandardErrorInSuccessfulOutput ? stderrText : "")
        )
    }

}

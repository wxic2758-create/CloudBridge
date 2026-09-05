import XCTest
@testable import CloudBridge

final class ProcessRunnerTests: XCTestCase {
    final class StreamCollector: @unchecked Sendable {
        let lock = NSLock()
        var streams: [ProcessOutputStream] = []
    }

    func testOutputHandlerReceivesBothStreams() async throws {
        let runner = ProcessRunner()
        let collector = StreamCollector()
        _ = try await runner.run(ProcessRequest(
            executable: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2"],
            outputHandler: { _, stream in
                collector.lock.lock(); collector.streams.append(stream); collector.lock.unlock()
            }
        ))
        XCTAssertTrue(collector.streams.contains(.standardOutput))
        XCTAssertTrue(collector.streams.contains(.standardError))
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

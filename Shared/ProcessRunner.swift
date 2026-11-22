import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

/// Runs one program directly (no shell) with a fixed argument list and a timeout.
/// Callers pass only paths and arguments from the fixed command lists; nothing here builds
/// a command from text.
enum ProcessRunner {
    private final class Box { var data = Data() }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // Minimal, fixed environment.
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        if let home = ProcessInfo.processInfo.environment["HOME"] { env["HOME"] = home }
        if let user = ProcessInfo.processInfo.environment["USER"] { env["USER"] = user }
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Drain both pipes concurrently so a full pipe can't stall the child.
        let out = Box(), err = Box()
        let group = DispatchGroup()
        for (pipe, box) in [(outPipe, out), (errPipe, err)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                box.data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }

        var timedOut = false
        let watchdog = DispatchWorkItem {
            if process.isRunning { timedOut = true; process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        group.wait()

        return ProcessResult(status: process.terminationStatus,
                             stdout: String(decoding: out.data, as: UTF8.self),
                             stderr: String(decoding: err.data, as: UTF8.self),
                             timedOut: timedOut)
    }
}

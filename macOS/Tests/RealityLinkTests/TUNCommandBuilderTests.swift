import XCTest
@testable import RealityLink

final class TUNCommandBuilderTests: XCTestCase {
    func testStartCommandHasValidShellSyntax() throws {
        let command = TUNCommandBuilder.startCommand(
            corePath: "/Applications/Reality Link's.app/Contents/Resources/sing-box",
            configPath: "/tmp/Reality Link/runtime.json",
            logPath: "/tmp/Reality Link/tun.log",
            pidPath: "/tmp/Reality Link/tun.pid",
            stopPath: "/tmp/Reality Link/tun.stop",
            reloadPath: "/tmp/Reality Link/tun.reload"
        )

        XCTAssertFalse(command.contains("&;"))
        XCTAssertFalse(command.contains("nohup"))
        XCTAssertTrue(command.contains("tun.stop"))
        XCTAssertTrue(command.contains("tun.reload"))
        XCTAssertTrue(command.contains("realitylink_child"))

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
    }

    func testStopSignalEndsPrivilegedWrapperWithoutSecondAuthorization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealityLink-TUN-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeCore = directory.appendingPathComponent("fake core.sh")
        try Data("#!/bin/sh\n/bin/sleep 10\n".utf8).write(to: fakeCore)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCore.path)
        let pidURL = directory.appendingPathComponent("tun.pid")
        let stopURL = directory.appendingPathComponent("tun.stop")
        let reloadURL = directory.appendingPathComponent("tun.reload")
        let command = TUNCommandBuilder.startCommand(
            corePath: fakeCore.path,
            configPath: directory.appendingPathComponent("runtime.json").path,
            logPath: directory.appendingPathComponent("tun.log").path,
            pidPath: pidURL.path,
            stopPath: stopURL.path,
            reloadPath: reloadURL.path
        )

        let process = Process()
        let pipe = Pipe()
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escapedCommand)\""]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: pidURL.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(process.isRunning)
        try Data("stop\n".utf8).write(to: stopURL)
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
    }

    func testReloadSignalRestartsChildButKeepsWrapperAlive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RealityLink-Reload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeCore = directory.appendingPathComponent("fake core.sh")
        try Data("#!/bin/sh\n/bin/sleep 10\n".utf8).write(to: fakeCore)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCore.path)
        let pidURL = directory.appendingPathComponent("tun.pid")
        let stopURL = directory.appendingPathComponent("tun.stop")
        let reloadURL = directory.appendingPathComponent("tun.reload")
        let command = TUNCommandBuilder.startCommand(
            corePath: fakeCore.path,
            configPath: directory.appendingPathComponent("runtime.json").path,
            logPath: directory.appendingPathComponent("tun.log").path,
            pidPath: pidURL.path,
            stopPath: stopURL.path,
            reloadPath: reloadURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()

        let firstPID = try waitForPID(at: pidURL)
        try Data("reload\n".utf8).write(to: reloadURL)
        let secondPID = try waitForPID(at: pidURL, differentFrom: firstPID)
        XCTAssertNotEqual(firstPID, secondPID)
        XCTAssertTrue(process.isRunning)

        try Data("stop\n".utf8).write(to: stopURL)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func waitForPID(at url: URL, differentFrom oldPID: String? = nil) throws -> String {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let value = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty, value != oldPID {
                return value
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw NSError(domain: "TUNCommandBuilderTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for child PID"])
    }
}

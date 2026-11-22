import XCTest

final class AllowedCommandsTests: XCTestCase {
    let ctx = CommandContext(wifiInterfaces: ["en1"], vpnIDs: ["10AF9C69-AC94-4FBC-A9B1-02507F693499"])

    func testWiFiUsesDetectedInterface() throws {
        let inv = try AllowedCommand.wifiPower(interface: "en1", on: false).invocation(in: ctx)
        XCTAssertEqual(inv.path, "/usr/sbin/networksetup")
        XCTAssertEqual(inv.arguments, ["-setairportpower", "en1", "off"])
    }

    func testWiFiRejectsOtherInterfaces() {
        for bad in ["en0", "en1; rm -rf ~", "", "../en1", "en1 "] {
            XCTAssertThrowsError(try AllowedCommand.wifiPower(interface: bad, on: true).invocation(in: ctx), bad) {
                XCTAssertEqual($0 as? CommandError, .unknownWiFiInterface(bad))
            }
        }
    }

    func testVPNOnlyKnownIDs() throws {
        let id = "10AF9C69-AC94-4FBC-A9B1-02507F693499"
        XCTAssertEqual(try AllowedCommand.vpnStart(id: id).invocation(in: ctx).arguments, ["--nc", "start", id])
        XCTAssertEqual(try AllowedCommand.vpnStop(id: id).invocation(in: ctx).arguments, ["--nc", "stop", id])
        // Tailscale's service ID is never in the context (the parser drops it), so it's refused.
        XCTAssertThrowsError(try AllowedCommand.vpnStart(id: "75ADE00F-131F-4E01-928C-FDD23464C3B9").invocation(in: ctx))
        XCTAssertThrowsError(try AllowedCommand.vpnStop(id: "-h").invocation(in: ctx))
    }

    func testTailscaleCommandsAreFixed() throws {
        let bin = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        let empty = CommandContext()
        XCTAssertEqual(try AllowedCommand.tailscaleUp.invocation(in: empty).arguments, ["up"])
        XCTAssertEqual(try AllowedCommand.tailscaleDown.invocation(in: empty).arguments, ["down"])
        XCTAssertEqual(try AllowedCommand.exitNodeOn.invocation(in: empty).arguments, ["set", "--exit-node=v2"])
        XCTAssertEqual(try AllowedCommand.exitNodeOff.invocation(in: empty).arguments, ["set", "--exit-node="])
        XCTAssertEqual(try AllowedCommand.tailscaleStatus.invocation(in: empty).path, bin)
    }

    func testEveryProgramIsAbsolute() throws {
        let all: [AllowedCommand] = [.wifiPower(interface: "en1", on: true), .tailscaleStatus, .tailscaleUp,
                                     .tailscaleDown, .exitNodeOn, .exitNodeOff, .vpnList,
                                     .vpnStart(id: "10AF9C69-AC94-4FBC-A9B1-02507F693499")]
        for c in all { XCTAssertTrue(try c.invocation(in: ctx).path.hasPrefix("/"), "\(c)") }
    }

    func testRequestRoundTrips() throws {
        let reqs: [ToggleRequest] = [.wifi(on: true), .tailscale(up: false), .exitNode(on: true),
                                     .vpn(id: "abc", connect: false)]
        let data = try JSONEncoder().encode(reqs)
        XCTAssertEqual(try JSONDecoder().decode([ToggleRequest].self, from: data), reqs)
    }

    func testProcessRunnerRunsWithoutShell() throws {
        // A shell metacharacter in an argument stays a literal argument.
        let r = try ProcessRunner.run("/bin/echo", ["a; echo injected"])
        XCTAssertEqual(r.stdout, "a; echo injected\n")
        XCTAssertEqual(r.status, 0)
    }

    func testProcessRunnerTimesOut() throws {
        let r = try ProcessRunner.run("/bin/sleep", ["5"], timeout: 0.5)
        XCTAssertTrue(r.timedOut)
    }
}

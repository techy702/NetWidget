import XCTest

final class ParserTests: XCTestCase {

    // Captured from `lsof -i -n -P -F pcPtnT` on the Mac mini, 2026-11-21.
    let lsofFixture = """
    p1094
    crapportd
    f11
    tIPv4
    PTCP
    n*:49161
    TST=LISTEN
    TQR=0
    TQS=0
    f21
    tIPv6
    PUDP
    n*:3722
    f22
    tIPv6
    PTCP
    n[fe80:10::85d:878f:bed:d258]:49161->[fe80:10::9d:2979:8e99:782]:61003
    TST=ESTABLISHED
    TQR=0
    TQS=0
    p1121
    cidentityservicesd
    f7
    tIPv4
    PUDP
    n*:*
    """

    func testLsofParsesEveryDescriptor() {
        let c = LsofParser.parse(lsofFixture)
        XCTAssertEqual(c.count, 4)

        XCTAssertEqual(c[0], Connection(command: "rapportd", pid: 1094, fd: "11", family: "IPv4", proto: "TCP",
                                        local: "*:49161", remote: nil, state: "LISTEN"))
        XCTAssertEqual(c[1].proto, "UDP")
        XCTAssertNil(c[1].state, "UDP has no TCP state")
        XCTAssertEqual(c[2].local, "[fe80:10::85d:878f:bed:d258]:49161")
        XCTAssertEqual(c[2].remote, "[fe80:10::9d:2979:8e99:782]:61003")
        XCTAssertEqual(c[2].state, "ESTABLISHED")
        XCTAssertEqual(c[3].command, "identityservicesd")
        XCTAssertEqual(c[3].pid, 1121)
    }

    func testLsofEmptyOutput() {
        XCTAssertEqual(LsofParser.parse(""), [])
    }

    func testTopPutsEstablishedFirstThenListen() {
        let all = LsofParser.parse(lsofFixture)
        let top = Connection.top(all, limit: 2)
        XCTAssertEqual(top.map(\.state), ["ESTABLISHED", "LISTEN"])
        XCTAssertEqual(Connection.top(all, limit: 10).count, 4)
    }

    // Captured from `scutil --nc list` on the Mac mini, 2026-11-21, plus one IPSec-style line
    // (no provider in parentheses) written to match scutil's format.
    let scutilFixture = """
    Available network connection services in the current set (*=enabled):
    * (Disconnected)   10AF9C69-AC94-4FBC-A9B1-02507F693499 VPN (ch.protonvpn.mac) "ProtonVPN"                      [VPN:ch.protonvpn.mac]
    * (Connected)      75ADE00F-131F-4E01-928C-FDD23464C3B9 VPN (io.tailscale.ipn.macsys) "Tailscale"                      [VPN:io.tailscale.ipn.macsys]
      (Connecting)     11111111-2222-3333-4444-555555555555 IPSec              "Office VPN"                     [IPSec]
    """

    func testVPNListSkipsTailscale() {
        let v = VPNListParser.parse(scutilFixture)
        XCTAssertEqual(v.map(\.name), ["ProtonVPN", "Office VPN"])
        XCTAssertEqual(v[0].id, "10AF9C69-AC94-4FBC-A9B1-02507F693499")
        XCTAssertEqual(v[0].provider, "ch.protonvpn.mac")
        XCTAssertEqual(v[0].status, "Disconnected")
        XCTAssertFalse(v[0].isConnected)
        XCTAssertNil(v[1].provider)
        XCTAssertTrue(v[1].isBusy)
    }

    // Hand-written with the field names seen in `tailscale status --json` (1.104.7) on the mini.
    func testTailscaleWithExitNode() {
        let json = """
        {"BackendState":"Running","TailscaleIPs":["100.107.6.65","fd7a:115c:a1e0::1031:642"],
         "Self":{"HostName":"mini","TailscaleIPs":["100.107.6.65"]},
         "Peer":{"k1":{"HostName":"v2","DNSName":"v2.example.ts.net.","TailscaleIPs":["100.115.222.113"],"ExitNode":true},
                 "k2":{"HostName":"phone","DNSName":"phone.example.ts.net.","ExitNode":false}}}
        """
        let t = TailscaleParser.parse(json)
        XCTAssertEqual(t?.running, true)
        XCTAssertEqual(t?.ips.first, "100.107.6.65")
        XCTAssertEqual(t?.exitNode, "v2")
    }

    func testTailscaleStopped() {
        let t = TailscaleParser.parse(#"{"BackendState":"Stopped","Peer":{}}"#)
        XCTAssertEqual(t?.running, false)
        XCTAssertNil(t?.exitNode)
        XCTAssertEqual(t?.backendState, "Stopped")
    }

    func testTailscaleGarbage() {
        XCTAssertNil(TailscaleParser.parse("failed to connect to local Tailscale service"))
    }
}

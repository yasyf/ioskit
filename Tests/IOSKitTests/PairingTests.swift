@testable import IOSKit
import Foundation
import Security
import Testing

@Suite("Pairing")
struct PairingTests {
    @Test("a well-formed v1 payload decodes")
    func pairPayloadDecodesGood() throws {
        let json = #"{"v":1,"url":"http://192.168.1.5:8765","token":"secret-abc"}"#
        let payload = try JSONDecoder().decode(PairPayload.self, from: Data(json.utf8))
        #expect(payload.version == 1)
        #expect(payload.url == URL(string: "http://192.168.1.5:8765"))
        #expect(payload.token == "secret-abc")
    }

    @Test("an unsupported version is rejected with PairError")
    func pairPayloadRejectsVersion() {
        let json = #"{"v":2,"url":"http://192.168.1.5:8765","token":"secret-abc"}"#
        #expect(throws: PairError.unsupportedVersion(2)) {
            try JSONDecoder().decode(PairPayload.self, from: Data(json.utf8))
        }
    }

    @Test("a payload without a token decodes as a tailnet pairing")
    func pairPayloadDecodesTokenless() throws {
        let json = #"{"v":1,"url":"https://studio.tail1234.ts.net:8765"}"#
        let payload = try JSONDecoder().decode(PairPayload.self, from: Data(json.utf8))
        #expect(payload.url == URL(string: "https://studio.tail1234.ts.net:8765"))
        #expect(payload.token == nil)
    }

    @Test("a tailnet pair link names the machine with no token")
    func pairLinkDecodes() throws {
        let link = try #require(URL(string: "ccpresent://pair?url=https%3A%2F%2Fstudio.tail1234.ts.net%3A8765"))
        let payload = try PairPayload(link: link, scheme: "ccpresent")
        #expect(payload.url == URL(string: "https://studio.tail1234.ts.net:8765"))
        #expect(payload.token == nil)
    }

    @Test("a pair link may still carry a token")
    func pairLinkCarriesToken() throws {
        let link = try #require(URL(string: "ccpresent://pair?url=http%3A%2F%2F10.0.0.2%3A8765&token=abc"))
        #expect(try PairPayload(link: link, scheme: "ccpresent").token == "abc")
    }

    @Test("a link for another app, another verb, or no http url is refused")
    func pairLinkRejectsOthers() throws {
        for raw in [
            "longrunning://pair?url=https%3A%2F%2Fstudio.ts.net",
            "ccpresent://open?url=https%3A%2F%2Fstudio.ts.net",
            "ccpresent://pair?url=file%3A%2F%2F%2Fetc%2Fpasswd",
            "ccpresent://pair",
        ] {
            let link = try #require(URL(string: raw))
            #expect(throws: PairError.notAPairLink) {
                try PairPayload(link: link, scheme: "ccpresent")
            }
        }
    }

    @Test("malformed JSON fails to decode")
    func pairPayloadRejectsGarbage() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PairPayload.self, from: Data("not json".utf8))
        }
    }

    @Test("the machine roster round-trips through an injected directory")
    func machineStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ioskit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MachineStore(directory: directory)
        #expect(try store.load().isEmpty)

        let machines = try [
            Machine(id: "m1", name: "Laptop", baseURL: #require(URL(string: "http://10.0.0.2:8765"))),
            Machine(id: "m2", name: "Studio", baseURL: #require(URL(string: "http://10.0.0.3:8765"))),
        ]
        try store.save(machines)

        let loaded = try store.load()
        #expect(loaded == machines)
    }

    @Test("a written token round-trips and delete clears it")
    func tokenRoundTrip() throws {
        let machineID = "ioskit-tests-\(UUID().uuidString)"
        let tokens = TokenStore(service: "ioskit-tests.v1")
        defer { try? tokens.deleteToken(machineID: machineID) }

        #expect(try tokens.token(machineID: machineID) == nil)
        try tokens.setToken("secret-abc", machineID: machineID)
        #expect(try tokens.token(machineID: machineID) == "secret-abc")
        try tokens.setToken("secret-xyz", machineID: machineID)
        #expect(try tokens.token(machineID: machineID) == "secret-xyz")
        try tokens.deleteToken(machineID: machineID)
        #expect(try tokens.token(machineID: machineID) == nil)
    }
}

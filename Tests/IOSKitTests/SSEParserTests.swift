@testable import IOSKit
import Foundation
import Testing

private func bytes(_ string: String) -> [UInt8] {
    Array(string.utf8)
}

@Suite("SSE parser")
struct SSEParserTests {
    @Test("a whole frame in one chunk dispatches one event with its id")
    func singleFrameOneChunk() throws {
        var parser = SSEParser()
        let events = parser.feed(bytes(#"id: 5\#ndata: {"type":"block.removed","id":"x"}\#n\#n"#))
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.event == "")
        #expect(event.data == #"{"type":"block.removed","id":"x"}"#)
        #expect(event.lastEventID == "5")
        #expect(parser.lastEventID == "5")
    }

    @Test("the named caught-up boundary event carries its own event name and seq data")
    func caughtUpNamedEvent() throws {
        var parser = SSEParser()
        let events = parser.feed(bytes(#"event: caught-up\#ndata: {"seq":42}\#n\#n"#))
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.event == "caught-up")
        #expect(event.data == #"{"seq":42}"#)
        // No id line rode with caught-up, so the reconnect cursor is untouched.
        #expect(event.lastEventID == nil)
    }

    @Test("comment lines and keepalives dispatch nothing but do not corrupt a following frame")
    func commentKeepalivesSkipped() {
        var parser = SSEParser()
        #expect(parser.feed(bytes(": connected\n\n")).isEmpty)
        #expect(parser.feed(bytes(": keepalive\n\n")).isEmpty)

        let events = parser.feed(bytes(#": keepalive\#n\#nid: 7\#ndata: {"type":"submit","revision":1}\#n\#n"#))
        #expect(events.count == 1)
        #expect(events.first?.data == #"{"type":"submit","revision":1}"#)
        #expect(events.first?.lastEventID == "7")
    }

    @Test("multi-line data joins with newline and drops the single trailing newline")
    func multiLineData() {
        var parser = SSEParser()
        let events = parser.feed(bytes("data: line1\ndata: line2\ndata: line3\n\n"))
        #expect(events.count == 1)
        #expect(events.first?.data == "line1\nline2\nline3")
    }

    @Test("one leading space after the colon is stripped, extra spaces are kept")
    func leadingSpaceHandling() {
        var single = SSEParser()
        #expect(single.feed(bytes("data:x\n\n")).first?.data == "x")

        var padded = SSEParser()
        #expect(padded.feed(bytes("data:  x\n\n")).first?.data == " x")
    }

    @Test("last-event-id persists across a frame that omits its own id")
    func lastEventIDPersists() {
        var parser = SSEParser()
        let first = parser.feed(bytes("id: 3\ndata: a\n\n"))
        #expect(first.first?.lastEventID == "3")

        let second = parser.feed(bytes("data: b\n\n"))
        #expect(second.first?.lastEventID == "3")
        #expect(parser.lastEventID == "3")
    }

    @Test("the reconnect cursor advances only when a frame fully dispatches")
    func lastEventIDAdvancesAtDispatch() {
        var parser = SSEParser()
        _ = parser.feed(bytes("id: 4\ndata: x\n\n"))
        #expect(parser.lastEventID == "4")

        // The id line is parsed, but no blank line has dispatched the frame yet, so
        // a drop here must still resume from 4 — not 9 — to avoid losing event 9.
        _ = parser.feed(bytes("id: 9\ndata: partial"))
        #expect(parser.lastEventID == "4")

        let events = parser.feed(bytes("\n\n"))
        #expect(events.count == 1)
        #expect(events.first?.data == "partial")
        #expect(events.first?.lastEventID == "9")
        #expect(parser.lastEventID == "9")
    }

    @Test("a retry field sets the reconnection time and dispatches no event")
    func retryField() {
        var parser = SSEParser()
        #expect(parser.feed(bytes("retry: 4500\n\n")).isEmpty)
        #expect(parser.reconnectionTime == 4500)

        // A non-numeric retry is ignored, leaving the prior value intact.
        _ = parser.feed(bytes("retry: soon\n\n"))
        #expect(parser.reconnectionTime == 4500)
    }

    @Test("CRLF and lone-CR terminators parse, including a CRLF split across chunks")
    func carriageReturnHandling() {
        var crlf = SSEParser()
        let events = crlf.feed(bytes("id: 1\r\ndata: x\r\ndata: y\r\n\r\n"))
        #expect(events.count == 1)
        #expect(events.first?.data == "x\ny")
        #expect(events.first?.lastEventID == "1")

        // The CR ends one chunk and the LF opens the next: the parser must coalesce
        // them into a single terminator, not emit a blank line for the stray CR.
        var split = SSEParser()
        var out = split.feed(bytes("data: hello\r"))
        out += split.feed(bytes("\ndata: world\r\n\r\n"))
        #expect(out.count == 1)
        #expect(out.first?.data == "hello\nworld")
    }

    @Test("a chunk boundary inside a multi-byte UTF-8 rune does not corrupt the data")
    func splitInsideRune() {
        // "é" encodes as C3 A9; the cut falls between its two bytes.
        let json = #"{"type":"input.submitted","blockId":"b","text":"café"}"#
        let all = Array(("data: " + json + "\n\n").utf8)
        let scalar = Array("é".utf8)
        var cut = 0
        for index in 0 ..< (all.count - 1) where all[index] == scalar[0] && all[index + 1] == scalar[1] {
            cut = index + 1
        }
        #expect(cut > 0)

        var parser = SSEParser()
        var events = parser.feed(Array(all[0 ..< cut]))
        events += parser.feed(Array(all[cut ..< all.count]))
        #expect(events.count == 1)
        #expect(events.first?.data == json)
    }

    @Test("a frame survives every two-way byte split, including mid-field and mid-rune")
    func everyTwoWaySplit() throws {
        let json = #"{"type":"reply.created","id":"r1","blockId":"b1","md":"café ☕ déjà"}"#
        let all = Array(("id: 7\ndata: " + json + "\n\n").utf8)
        for cut in 1 ..< all.count {
            var parser = SSEParser()
            var events = parser.feed(Array(all[0 ..< cut]))
            events += parser.feed(Array(all[cut ..< all.count]))
            #expect(events.count == 1, "split at \(cut) produced \(events.count) events")
            let event = try #require(events.first)
            #expect(event.event == "")
            #expect(event.data == json, "split at \(cut) corrupted the data")
            #expect(event.lastEventID == "7")
        }
    }
}

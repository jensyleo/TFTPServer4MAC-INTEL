// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class TransferActivityParserTests: XCTestCase {
    func testParsesFilenameLineWithPID() {
        let event = TransferActivityParser.parse(line: "2026-09-07 07:15:00.000 I  tftpd[38082:17258d] Filename: 'bigfile.bin'")
        guard case .filenameDetected(let pid, let filename) = event else {
            return XCTFail("Expected .filenameDetected, got \(String(describing: event))")
        }
        XCTAssertEqual(pid, 38082)
        XCTAssertEqual(filename, "bigfile.bin")
    }

    func testDistinguishesConcurrentPIDs() {
        let eventA = TransferActivityParser.parse(line: "tftpd[100:1] Filename: 'a.bin'")
        let eventB = TransferActivityParser.parse(line: "tftpd[200:1] Filename: 'b.bin'")
        guard case .filenameDetected(let pidA, _) = eventA, case .filenameDetected(let pidB, _) = eventB else {
            return XCTFail("Expected both to parse")
        }
        XCTAssertNotEqual(pidA, pidB)
    }

    func testIgnoresUnrelatedLines() {
        XCTAssertNil(TransferActivityParser.parse(line: "tftpd[38082:17258d] Mode: 'octet'"))
        XCTAssertNil(TransferActivityParser.parse(line: "Some unrelated log line"))
    }

    /// Formato real del `tftpd` de macOS 13 Ventura (bug real encontrado en
    /// vivo, 2026-09-08): sin este caso, el parser solo reconocía el formato
    /// de Tahoe y nunca detectaba ninguna transferencia en Ventura.
    func testParsesVenturaReadRequestLine() {
        let event = TransferActivityParser.parse(
            line: "2026-09-08 14:02:56.720 I  tftpd[15662:119fac] 10.4.200.143: read request for /private/tmp/tftproot/neutro.txt: success"
        )
        guard case .filenameDetected(let pid, let filename) = event else {
            return XCTFail("Expected .filenameDetected, got \(String(describing: event))")
        }
        XCTAssertEqual(pid, 15662)
        XCTAssertEqual(filename, "neutro.txt")
    }

    func testParsesVenturaWriteRequestLine() {
        let event = TransferActivityParser.parse(
            line: "2026-09-08 14:07:32.162 I  tftpd[16653:11b60b] 10.4.200.143: write request for /private/tmp/tftproot/subida-check.txt: success"
        )
        guard case .filenameDetected(let pid, let filename) = event else {
            return XCTFail("Expected .filenameDetected, got \(String(describing: event))")
        }
        XCTAssertEqual(pid, 16653)
        XCTAssertEqual(filename, "subida-check.txt")
    }

    func testIgnoresVenturaFailureLines() {
        XCTAssertNil(TransferActivityParser.parse(
            line: "tftpd[12564:115250] 10.4.200.143: read request for testfinal.txt: File not found"
        ))
    }
}

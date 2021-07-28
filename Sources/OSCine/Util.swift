//
//  File.swift
//  
//
//  Created by Frank Vernon on 7/4/21.
//

import Foundation
import Network
import OSLog

//MARK: - Logging

internal var OSCNetworkLogger: Logger = {
    Logger(subsystem: "com.cyberdev.OSCine",
           category: "network")
}()

//MARK: - Data Padding

//Data extension to add padding as required by OSC
extension Data {
    //All OSC data is zero padded modulo 4 bytes
    fileprivate static let kOSCPadValue: UInt8 = 0
    fileprivate static let kOSCPadModulo: Int = 4

    //Returns the number of bytes required to pad to the next OSC alignment boundary
    static func OSCPadding(for count: Int) -> Int {
        guard count > .zero else {
            return .zero
        }
        
        let padding = count.remainderReportingOverflow(dividingBy: Data.kOSCPadModulo).partialValue
        return padding > .zero ? Data.kOSCPadModulo - padding : .zero
    }

    mutating func OSCPad() {
        append(Data(repeating: Data.kOSCPadValue,
                    count: Data.OSCPadding(for: count)))
    }

    func OSCPadded() -> Data {
        var result = self
        result.OSCPad()
        return result
    }
}

//MARK: - Data Parsing

extension Data {
    //returns range of next set of null terminated bytes following
    // the given index, after first walking over any preceeding nulls
    func nextCStr(after start: Data.Index) -> Range<Int>? {
        guard let begins = self[start...].firstIndex(where: { $0 != 0 }),
              let ends = self[begins...].firstIndex(where: { $0 == 0 }) else {
            return nil
        }

        return begins..<ends
    }
}

//MARK: - Array

extension Array {
    //helpful init to reserve array capacity at creation time
    init(capacity: Int) {
        self.init()
        reserveCapacity(capacity)
    }
}

//MARK: - NWProtocolUDP

extension NWProtocolUDP {
    static var maxDatagramSize: Int = {
        65507 //IPv4
    }()
}

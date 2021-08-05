//
//  Util.swift
//  
//
//  Created by Frank Vernon on 7/4/21.
//

import Foundation
import Network
import OSLog

//MARK: - Definitions

public let kOSCServiceTypeUDP: String = "_osc._udp"
public let kOSCServiceTypeTCP: String = "_osc._tcp"

public enum OSCNetworkingError: Error {
    case invalidNetworkDesignation
    case notConnected
}

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
    //Returns range of next set of null terminated bytes following
    // the given index, after first walking over any leading nulls
    func nextCStr(after start: Data.Index) -> Range<Int>? {
        guard let begins = self[start...].firstIndex(where: { $0 != 0 }),
              let ends = self[begins...].firstIndex(where: { $0 == 0 }) else {
            return nil
        }
        
        return begins..<ends
    }
    
    //Attempts to decode data to appropriate OSCPacketContents
    // type based on leading char
    func parseOSCPacket() throws -> OSCBundleElement {
        guard let first = first else {
            throw OSCCodingError.invalidPacket
        }
        
        switch Character(UnicodeScalar(first)) {
        case OSCBundle.kOSCBundlePrefix:
            return try OSCBundle(packet: self)
            
        case OSCAddressPattern.kOSCPartDelim:
            return try OSCMessage(packet: self)
            
        default:
            throw OSCCodingError.invalidPacket
        }
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
    /// Max datagram payload size
    ///
    /// - Note:This is the more conservative of the IPv6 and IPv4 sizes for simplicity.
    static var maxDatagramSize: Int = {
        65507
    }()
}

//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/5/21.
//

import Foundation

//MARK: - OSCBundleElement

public protocol OSCBundleElement {
    init(packet: Data) throws
    func packet() throws -> Data
}

public typealias OSCBundleElementArray = Array<OSCBundleElement>


//MARK: - Bundle

///A Bundle is a collection of Messages and/or other Bundles.
///It consists of a `TimeTag` and one or more `Elements`. Elements
///may be `Messages` or other `Bundles`.
///
///Bundles are a convenient way to send multiple messages in a single packet.
///More importantly, however, they are used to indicate when sets of messages
///should be applied simultaneously on the server, possibly at a future date.
public class OSCBundle: OSCBundleElement {
    static let kOSCBundleIdentifier = "#bundle"
    static let kOSCBundlePrefix: Character = "#"

    public var timeTag: OSCTimeTag? = nil
    public var elements: OSCBundleElementArray? = nil
    
    public init() {}
    public required init(packet: Data) throws {
        //First null terminated string is bundle ident
        guard let identRange = packet.nextCStr(after: packet.startIndex),
              let ident = String(data: packet[identRange], encoding: .utf8),
              ident == OSCBundle.kOSCBundleIdentifier else {
            throw OSCCodingError.invalidBundle
        }
        
        //read time tag
        var currPos = 8 //step over ident
        timeTag = try OSCTimeTag.OSCDecode(data: packet, at: &currPos)
        
        //read bundleElements from data
        elements = OSCBundleElementArray()
        while currPos < packet.endIndex {
            let bundleData = packet[currPos...]
            
            //get size from front of data
            let size = try Int32.OSCDecode(data: bundleData, at: &currPos)
            
            //read data based on size
            let packetData = bundleData[currPos..<(currPos + Int(size))]
            
            //decode element and append to array
            let element = try packetData.parseOSCPacket()
            switch element {
            case is OSCMessage:
                break
            case let bundle as OSCBundle:
                guard let bundleTime = bundle.timeTag, let time = timeTag,
                      bundleTime >= time else {
                    //This time tag check is per the spec, may be a bit overkill
                    throw OSCCodingError.invalidBundle
                }
            default:
                throw OSCCodingError.invalidBundle
            }
            elements?.append(element)
            
            //step over processed data
            currPos += Int(size)
        }
    }

    public init(timeTag: OSCTimeTag = .immediate, elements: OSCBundleElementArray) {
        self.timeTag = timeTag
        self.elements = elements
    }
    
    ///Adds an element to the end of the array of elements for this bundle
    public func append(element: OSCBundleElement) {
        if elements == nil {
            elements = OSCBundleElementArray()
        }
        elements?.append(element)
    }
    
    ///Returns an OSC encoded representation of the bundle suitable for
    /// transmission to a server.
    public func packet() throws -> Data {
        guard let timeTag = timeTag,
              let elements = elements else {
            throw OSCCodingError.invalidBundle
        }
        
        var packet = Data()
        packet.append(try OSCBundle.kOSCBundleIdentifier.OSCEncode())
        packet.append(try timeTag.OSCEncode())
        try elements.forEach {
            let element = try $0.packet()
            packet.append(try Int32(element.count).OSCEncode())
            packet.append(element)
        }
        return packet
    }
}

extension OSCBundleElementArray {
    public static func == (lhs: OSCBundleElementArray, rhs: OSCBundleElementArray) -> Bool {
        lhs.elementsEqual(rhs) {
            do {
                let left = try $0.packet()
                let right = try $1.packet()
                return left == right
            } catch {
                return false
            }
        }
    }
}

extension OSCBundle: Equatable {
    public static func == (lhs: OSCBundle, rhs: OSCBundle) -> Bool {
        guard lhs.timeTag == rhs.timeTag else {
            return false
        }

        //check bundle elements match
        switch (lhs.elements, rhs.elements) {
        case (.some, .none):
            fallthrough
        case (.none, .some):
            return false

        case (.none, .none):
            return true

        case (.some(let left), .some(let right)):
            return left == right
        }
    }
}

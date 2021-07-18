//
//  OSCine.swift
//
//
//  Created by Frank Vernon on 6/29/21.
//
// Swift implementation of OSC 1.1
//
//http://opensoundcontrol.org/spec-1_0.html
//http://opensoundcontrol.org/files/2009-NIME-OSC-1.1.pdf

import Foundation

//MARK: - Definitions

public enum OSCEncodingError: Error {
    case stringEncodingFailure
    case invalidArgumentList
    case invalidMessage
    case invalidBundle
    case invalidAddress
}

enum OSCDataTypeTag: Character {
    //1.0
    case int = "i"
    case float = "f"
    case string = "s"
    case blob = "b"
    
    //1.1
    case `true` = "T"
    case `false` = "F"
    case null = "N"
    case impulse = "I"
    case timetag = "t"
}

public enum OSCPatternMatchType: Comparable {
    case none
    case container
    case full
}

extension OSCDataTypeTag {
    var tagData: Data {
        guard let intValue: UInt8 = self.rawValue.asciiValue else {
            fatalError("Fatal error rendering OSC tag data")
        }
        
        return Data([intValue])
    }
}

//MARK: - OSCDataType Protocol

//Protocol for specifying valid OSC Data Types
protocol OSCDataType {
    func OSCEncoded() throws -> Data
    
    var tag: OSCDataTypeTag { get }
}

extension OSCDataType {
    //Many OSC Data types have no associated data thus this defaul implementation
    func OSCEncoded() throws -> Data { Data() }
}

//MARK: - Data Types

//OSC Data Types
public typealias OSCInt = Int32
extension OSCInt: OSCDataType {
    var tag: OSCDataTypeTag { .int }
    
    func OSCEncoded() throws -> Data {
        var source = self.bigEndian
        return Data(bytes: &source, count: MemoryLayout<Self>.size)
    }
    
    static func OSCDecoded(data: Data, at offset: inout Data.Index) throws -> OSCInt {
        guard data.endIndex >= offset + 4 else {
            throw OSCEncodingError.invalidMessage
        }
        
        let result = data.subdata(in: offset..<offset + 4).withUnsafeBytes {
            $0.load(as: Int32.self)
        }.bigEndian
        
        offset += 4
        return result
    }
}

public typealias OSCFloat = Float32
extension OSCFloat: OSCDataType {
    var tag: OSCDataTypeTag { .float }
    
    func OSCEncoded() throws -> Data {
        var float: CFSwappedFloat32 = CFConvertFloatHostToSwapped(self)
        let size: Int = MemoryLayout<CFSwappedFloat32>.size
        let result: [UInt8] = withUnsafePointer(to: &float) {
            $0.withMemoryRebound(to: UInt8.self, capacity: size) {
                Array(UnsafeBufferPointer(start: $0, count: size))
            }
        }
        return Data(result)
    }
    
    static func OSCDecoded(data: Data, at offset: inout Data.Index) throws -> OSCFloat {
        guard data.endIndex >= offset + 4 else {
            throw OSCEncodingError.invalidMessage
        }

        let result = data.subdata(in: offset..<offset + 4).withUnsafeBytes {
            CFConvertFloat32SwappedToHost($0.load(as: CFSwappedFloat32.self))
        }
        
        offset += 4
        return result
    }
}

public typealias OSCBool = Bool
extension OSCBool: OSCDataType {
    var tag: OSCDataTypeTag { self ? .true : .false }
}

public struct OSCTimeTag: Codable, Equatable, Comparable {
    var seconds: UInt32
    var picoseconds: UInt32
        
    var date: Date {
        var interval = TimeInterval(seconds)
        interval += TimeInterval(Double(picoseconds) / 0xffffffff)
        return OSCTimeTag.OSCEpoch.addingTimeInterval(interval)
    }
    
    var immediate: Bool {
        seconds == 0 && picoseconds == 1
    }
    
    public init(immediate: Bool = false) {
        seconds = 0
        picoseconds = 0

        if immediate {
            picoseconds = 1
        }
    }
    
    public init(seconds: UInt32, picoseconds: UInt32) {
        self.seconds = seconds
        self.picoseconds = picoseconds
    }
    
    public init(withDate date: Date) {
        let secondsSinceOSCEpoch = date.timeIntervalSince(OSCTimeTag.OSCEpoch)
        
        seconds = UInt32(UInt64(secondsSinceOSCEpoch) & 0xffffffff)
        picoseconds = UInt32(fmod(secondsSinceOSCEpoch, 1.0) * Double(0xffffffff))
    }
    
    public static func < (lhs: OSCTimeTag, rhs: OSCTimeTag) -> Bool {
        lhs.date < rhs.date
    }
    
    private static var OSCEpoch: Date = {
        //midnight on January 1, 1900
        let components = DateComponents(calendar: Calendar(identifier: .gregorian),
                                        year: 1900,
                                        month: 1,
                                        day: 1,
                                        hour: 0)
        guard let origin = components.date else {
            fatalError("OSC Epoch Date could not be computed")
        }
        
        return origin
    }()
}

extension OSCTimeTag: OSCDataType {
    var tag: OSCDataTypeTag { .timetag }
    
    func OSCEncoded() throws -> Data {
        func encodeUInt32(_ value:UInt32) -> Data {
            var source = value.bigEndian
            return Data(bytes: &source, count: MemoryLayout<UInt32>.size)
        }
        
        var result = encodeUInt32(seconds)
        result.append(encodeUInt32(picoseconds))
        
        return result
    }
    
    static func OSCDecoded(data: Data, at offset: inout Data.Index) throws -> OSCTimeTag {
        guard data.endIndex >= offset + 8 else {
            throw OSCEncodingError.invalidMessage
        }
        
        let start = data.startIndex + offset
        
        let seconds = data.subdata(in: start ..< start + 4).withUnsafeBytes {
            $0.load(as: UInt32.self)
        }.byteSwapped
        
        let picoseconds = data.subdata(in: start + 4 ..< start + 8).withUnsafeBytes {
            $0.load(as: UInt32.self)
        }.byteSwapped
        
        offset += 8
        return OSCTimeTag(seconds: seconds, picoseconds: picoseconds)
    }
}

public typealias OSCString = String
extension OSCString: OSCDataType {
    var tag: OSCDataTypeTag { .string }
    
    func OSCEncoded() throws -> Data {
        guard var data = data(using: .utf8) else {
            throw OSCEncodingError.stringEncodingFailure
        }
        
        //append NULL terminator, per spec
        data.append(0)
        data.OSCPad()
        
        return data
    }
    
    static func OSCDecoded(data: Data, at offset: inout Data.Index) throws -> OSCString {
        guard let stringRange = data.nextCStr(after: offset),
              let result = String(data: data[stringRange], encoding: .utf8) else {
            throw OSCEncodingError.invalidMessage
        }
        offset += stringRange.count + Data.OSCPadding(for: stringRange.count)
        
        return result
    }
}

public typealias OSCBlob = Data
extension OSCBlob: OSCDataType {
    var tag: OSCDataTypeTag { .blob }
    
    func OSCEncoded() throws -> Data {
        var blob = try OSCInt(count).OSCEncoded()
        blob.append(self)
        blob.OSCPad()
        return blob
    }
    
    static func OSCDecoded(data: Data, at offset: inout Data.Index) throws -> OSCBlob {
        let blobSize = try OSCInt.OSCDecoded(data: data, at: &offset)
        let endData = offset + Int(blobSize)
        guard endData < data.endIndex else {
            throw OSCEncodingError.invalidMessage
        }
        let result = data.subdata(in: offset..<endData)
        
        offset += Int(blobSize) + OSCPadding(for: Int(blobSize))
        
        return result
    }
}

public struct OSCNull: OSCDataType {
    var tag: OSCDataTypeTag { .null }
}

public struct OSCImpulse: OSCDataType {
    var tag: OSCDataTypeTag { .impulse }
}

public typealias OSCAddressPattern = OSCString
extension OSCAddressPattern {
    static let OSCAddressPartDelimiter: Character = "/"
    
    //Set of reserved characters which are not allowed in
    // address patterns
    enum reserved: Character, CaseIterable {
        case space = " "
        case hash = "#"
        case comma = ","
        case matchSingle = "?"
        case matchAny = "*"
        case matchRange = "["
        case matchRangeEnd = "]"
        case matchString = "{"
        case matchStringEnd = "}"
        
        static var reservedCharSet: CharacterSet = {
            CharacterSet(charactersIn: allCases.reduce(into: String()) {$0.append($1.rawValue)})
        }()
    }
    
    func isValidOSCAddress() -> Bool {
        first == String.OSCAddressPartDelimiter
            && reserved.reservedCharSet.isDisjoint(with: CharacterSet(charactersIn: self))
    }
        
    //Theory of operation...
    //  Walk the pattern and address char by char matching chars based on
    //  rules of the various wildcard elements. Break out of loop
    //  on first occurance of a non-match.
    //
    // I considered doing this on Data instead but String is the natural
    // data type for addresses and patterns so I'm doing this all here.
    func oscMethodAddressMatch(pattern: String) -> OSCPatternMatchType {
        var addressPos = startIndex
        var patternPos = pattern.startIndex
        
        func addressInc(_ count: Int = 1) {
            //note: this is potentially unsafe - may walk past end
            // we are in theory protected by logic used below
            addressPos = index(addressPos, offsetBy: count)
        }

        func currAddressChar() -> Character? {
            addressPos < endIndex ? self[addressPos] : nil
        }
        
        func currAddressSegment() -> Substring {
            guard let segment = self[addressPos...].range(of: "/") else {
                return self[addressPos...]
            }
            return self[addressPos..<segment.lowerBound]
        }

        func prevAddressChar() -> Character? {
            guard addressPos > startIndex else {
                return nil
            }
            return self[index(addressPos, offsetBy: -1)]
        }

        func patternInc() {
            patternPos = pattern.index(after: patternPos)
        }

        func currPatternChar() -> Character? {
            patternPos < pattern.endIndex ? pattern[patternPos] : nil
        }
        
        func bracketCharSet() -> (Bool, Array<Character>)? {
            guard currPatternChar() == "[" else {
                return nil
            }
            
            var inverted = false
            var charray = Array<Character>()
            //get set of chars between brackers,
            while true {
                patternInc()
                
                // if we hit end or end of segment we have an error
                guard let current = currPatternChar(), current != "/" else {
                    return nil
                }
                
                guard current != "]" else {
                    patternInc()
                    break
                }
                
                charray.append(current)
            }
            
            //check for inverted meaning
            if let first = charray.first, first == "!" {
                inverted = true
                charray.removeFirst()
            }
            
            //expand any/all dash ranges
            while let dash = charray.firstIndex(of: "-") {
                //ensure dash is not at head or tail of the charray
                guard dash > charray.startIndex && dash < charray.endIndex else {
                    return nil
                }
                var charRangeStart = charray[dash-1]
                let charRangeEnd = charray[dash+1]
                
                var rangeArray = Array<Character>()
                while let start = charRangeStart.asciiValue, let end = charRangeEnd.asciiValue, start <= end {
                    rangeArray.append(charRangeStart)
                    charRangeStart = Character(UnicodeScalar(start+1))
                }
                charray.replaceSubrange(dash-1...dash+1, with: rangeArray)
            }
            
            return (inverted, charray)
        }
        
        func parenStringSet() -> [Self.SubSequence]? {
            guard currPatternChar() == "{" else {
                return nil
            }
            
            //get set of chars between parens
            var strings = String()
            while true {
                patternInc()
                
                // if we hit end or end of segment we have an error
                guard let current = currPatternChar(), current != "/" else {
                    return nil
                }
                
                guard current != "}" else {
                    patternInc()
                    break
                }
                
                strings.append(current)
            }
            
            return strings.split(separator: ",")
        }
        
        patternLoop: while currPatternChar() != nil {
            let startPattern = patternPos
            switch currPatternChar() {
            case "?":
                //match any single char, except segment termination or end of address
                // i.e. there must be at least one more char before
                // the segment termination or end of address:
                // /foo/bar? would match: /foo/bar1, but not /foo/bar/1 or /foo/bar
                guard let current = currAddressChar(), current != "/" else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }

                patternInc()
                addressInc()
                
            case "*":
                //match zero or more chars, except segment termination or end of address
                // /foo/bar* would match: /foo/bar1111 or /foo/bar, but not /foo/bar/1111
                patternInc()
                while let current = currAddressChar(), current != "/", current != currPatternChar() {
                    addressInc()
                }
                
            case "[":
                //match any single char based on the set of characters expressed in the brackets,
                // except segment termination or end of address
                // i.e. there must be at least one more char before
                // the segment termination or end of address:
                // /foo/bar[1-2] would match: /foo/bar1, but not /foo/bar/1 or /foo/bar
                guard let current = currAddressChar(), current != "/",
                      let (inverted, charray) = bracketCharSet(),
                      charray.contains(current) != inverted else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }
                
                //bracketCharSet() increments the patternPos for us
                addressInc()

            case "{":
                //match (sub)string in segment based on set of strings in the parens,
                // /foo/{bar,bar1} would match: /foo/bar or /foo/bar1, but not /foo/bar/1
                // Note that we prefer the longest possible match over order
                // of strings in pattern
                let addrSegment = currAddressSegment()
                guard let strings = parenStringSet()?.sorted(by: {$0.count > $1.count}),
                      let match = strings.first(where: {addrSegment.hasPrefix($0)}) else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }
                                
                //parenStringSet() increments the patternPos for us
                addressInc(match.count)

            case "/":
                //Segment termination or possible start of XPath wildcard
                // regardless check that current address is also starting
                // at segment termination if not bail out
                guard let current = currAddressChar(), current == "/" else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }

                patternInc()
                addressInc()
                
                //check for XPath wildcard in pattern
                if currPatternChar() == "/" {
                    patternInc()

                    //Match remaining segments of the pattern with remaining segments of the address
                    var bestMatch: OSCPatternMatchType = .none
                    while true {
                        guard patternPos != pattern.endIndex, addressPos != endIndex else {
                            addressPos = endIndex
                            patternPos = startPattern
                            break patternLoop
                        }

                        let remainingAddress = String(self[addressPos...])
                        let remainingPattern = String(pattern[patternPos...])
                        
                        //Here Be Dragons
                        let match = remainingAddress.oscMethodAddressMatch(pattern: remainingPattern)
                        bestMatch = match > bestMatch ? match : bestMatch
                        if bestMatch == .full {
                            break
                        }
                        
                        guard let nextSegment = self[addressPos...].range(of: "/") else {
                            break
                        }
                        
                        addressPos = self.index(after: nextSegment.lowerBound)
                    }
                    
                    return bestMatch
                }
                
            default:
                //match characters
                guard let addrChar = currAddressChar(), addrChar == currPatternChar() else {
                    break patternLoop
                }
                
                patternInc()
                addressInc()
            }
        }
        
        //address fully matched pattern
        if addressPos == endIndex && patternPos == pattern.endIndex {
            return .full
        }
        
        //address shorter than pattern
        else if addressPos == endIndex && patternPos != pattern.endIndex {
            return .none
        }
        
        //pattern shorter than address - check to see if we are at address segment termination
        else if patternPos == pattern.endIndex && currAddressChar() == "/" {
            return .container
        }
        
        //pattern shorter than address - edge case pattern ends in segment termination
        else if patternPos == pattern.endIndex && (pattern.last == "/" && prevAddressChar() == "/") {
            return .container
        }

        return .none
    }
}

//MARK: - OSC Packets

//Trivial factory class to create OSCPacketContents from data
// …annoying that Swift does not support static functions on protocols
struct OSCPacketFactory {
    static func decodeOSCPacket(packet: Data) throws -> OSCPacketContents {
        guard let first = packet.first else {
            throw OSCEncodingError.invalidBundle
        }
        
        switch Character(UnicodeScalar(first)) {
        case OSCBundle.kOSCBundlePrefix:
            return try OSCBundle(packet: packet)
            
        case OSCAddressPattern.OSCAddressPartDelimiter:
            return try OSCMessage(packet: packet)
            
        default:
            throw OSCEncodingError.invalidBundle
        }
    }
}

//Protocol defining basic OSCPacket contents and operations on the contents
protocol OSCPacketContents {
    func createPacket() throws -> OSCPacket
    func parsePacket(packet: OSCPacket) throws
}

//MARK: - OSCMessage

public class OSCMessage {
    var addressPattern: OSCAddressPattern? = nil
    var arguments: OSCArgumentArray? = nil
    var argumentTypes: OSCTypeTagArray? {
        arguments?.typeTags()
    }
    
    convenience init(address: OSCAddressPattern, arguments: OSCArgumentArray) {
        self.init()
                
        self.addressPattern = address
        self.arguments = arguments
    }
    
    convenience init(packet: OSCPacket) throws {
        self.init()
        try parsePacket(packet: packet)
    }
    
    func appendArgument(_ arg: OSCDataType) {
        if arguments == nil {
            arguments = OSCArgumentArray()
        }
        arguments?.append(arg)
    }
    
    func argumentsMatch(_ types: OSCTypeTagArray) -> Bool {
        return types == argumentTypes
    }
}

extension OSCMessage: OSCPacketContents {
    func createPacket() throws -> OSCPacket {
        guard let address = addressPattern,
              let arguments = arguments else {
            throw OSCEncodingError.invalidMessage
        }

        var packet = OSCPacket()
        packet.append(try address.OSCEncoded())
        packet.append(try arguments.typeTags().tagDescription())
        packet.append(try arguments.OSCEncoded())
        
        return packet
    }
    
    func parsePacket(packet: OSCPacket) throws {
        //First null terminated string is path
        //Second null terminated string is tag types
        //tag types must begin with a ',' character
        guard let pathRange = packet.nextCStr(after: packet.startIndex),
              let tagTypesRange = packet.nextCStr(after: pathRange.endIndex),
              let path = String(data: packet[pathRange], encoding: .utf8),
              let tagTypes = String(data: packet[tagTypesRange], encoding: .utf8),
              tagTypes.first == "," else {
            throw OSCEncodingError.invalidMessage
        }

        //get pointer to tag data corresponding to tag type list
        let tagDataOffset = tagTypesRange.endIndex + Data.OSCPadding(for: tagTypesRange.endIndex)
        let tagData = packet[tagDataOffset...]
        var currPos = tagData.startIndex
        
        //parse tag data based on tag type definition
        let types = try OSCTypeTagArray.from(string: tagTypes)
        var argArray = OSCArgumentArray(capacity: types.count)
        try types.forEach { type in
            switch type {
            case .int:
                let int = try OSCInt.OSCDecoded(data: tagData, at: &currPos)
                argArray.append(int)
            case .float:
                let float = try OSCFloat.OSCDecoded(data: tagData, at: &currPos)
                argArray.append(float)
            case .string:
                let string = try OSCString.OSCDecoded(data: tagData, at: &currPos)
                argArray.append(string)
            case .blob:
                let blob = try OSCBlob.OSCDecoded(data: tagData, at: &currPos)
                argArray.append(blob)
            case .true:
                argArray.append(OSCBool(true))
            case .false:
                argArray.append(OSCBool(false))
            case .null:
                argArray.append(OSCNull())
            case .impulse:
                argArray.append(OSCImpulse())
            case .timetag:
                let timetag = try OSCTimeTag.OSCDecoded(data: tagData, at: &currPos)
                argArray.append(timetag)
            }
        }
        
        addressPattern = path
        arguments = argArray
    }
}

//MARK: - OSCBundle

public class OSCBundle {
    static let kOSCBundlePrefix: Character = "#"
    static let kOSCBundleIdentifier = "#bundle"
    
    var timeTag: OSCTimeTag? = nil
    var bundleElements: OSCPacketContentsArray? = nil
        
    init() {
    }
    
    init(timeTag: OSCTimeTag, bundleElements: OSCPacketContentsArray) {
        self.timeTag = timeTag
        self.bundleElements = bundleElements
    }
    
    init(packet: OSCPacket) throws {
        try parsePacket(packet: packet)
    }
    
    func appendMessage(_ message: OSCMessage) {
        appendContents(message)
    }
    
    func appendBundle(_ bundle: OSCBundle) {
        appendContents(bundle)
    }
    
    func appendContents(_ contents: OSCPacketContents) {
        if bundleElements == nil {
            bundleElements = OSCPacketContentsArray()
        }
        bundleElements?.append(contents)
    }
}

extension OSCBundle: OSCPacketContents {
    func createPacket() throws -> OSCPacket {
        guard let timeTag = timeTag,
              let bundleElements = bundleElements else {
            throw OSCEncodingError.invalidBundle
        }
        
        let bundleIdent = OSCString(OSCBundle.kOSCBundleIdentifier)
        
        var packet = OSCPacket()
        packet.append(try bundleIdent.OSCEncoded())
        packet.append(try timeTag.OSCEncoded())
        packet.append(try bundleElements.packedContents())
        
        return packet
    }
    
    func parsePacket(packet: OSCPacket) throws {
        //First null terminated string is bundle ident
        guard let identRange = packet.nextCStr(after: packet.startIndex),
              let ident = String(data: packet[identRange], encoding: .utf8),
              ident == OSCBundle.kOSCBundleIdentifier else {
            throw OSCEncodingError.invalidBundle
        }
                
        //read time tag
        var currPos = 8 //step over ident
        timeTag = try OSCTimeTag.OSCDecoded(data: packet, at: &currPos)

        //read bundleElements
        bundleElements = OSCPacketContentsArray()
        while currPos < packet.endIndex {
            let bundleData = packet[currPos...]

            //get size from front of data
            let size = try OSCInt.OSCDecoded(data: bundleData, at: &currPos)

            //read data based on size
            let packetData = bundleData[currPos..<currPos + Int(size)]
            
            //decode element and append to array
            let element = try OSCPacketFactory.decodeOSCPacket(packet: packetData)
            switch element {
            case is OSCMessage:
                break
            case let bundle as OSCBundle:
                guard let bundleTime = bundle.timeTag, let time = timeTag,
                      bundleTime >= time else {
                    //This time tag check is per the spec, may be a bit overkill
                    throw OSCEncodingError.invalidBundle
                }
            default:
                throw OSCEncodingError.invalidBundle
            }
            bundleElements?.append(element)

            //step over processed data
            currPos += Int(size)
        }
    }
}

extension OSCMessage: Equatable {
    public static func == (lhs: OSCMessage, rhs: OSCMessage) -> Bool {
        //check addresses match
        guard lhs.addressPattern == rhs.addressPattern else {
            return false
        }
                
        //check arguments match
        switch (lhs.arguments, rhs.arguments) {
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

extension OSCBundle: Equatable {
    public static func == (lhs: OSCBundle, rhs: OSCBundle) -> Bool {
        guard lhs.timeTag == rhs.timeTag else {
            return false
        }
        
        //check bundle elements match
        switch (lhs.bundleElements, rhs.bundleElements) {
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

typealias OSCPacket = Data
extension OSCPacket {
    init(packetContents: OSCPacketContents) throws {
        self.init()
        
        self = try packetContents.createPacket()
    }
    
    init(bundle: OSCBundle) throws {
        self.init()
    }
}

//MARK: - OSCTypeTagArray

typealias OSCTypeTagArray = Array<OSCDataTypeTag>
extension OSCTypeTagArray {
    fileprivate static var kOSCTagTypePrefix: Character = ","
    fileprivate static var prefixData: Data = {
        guard let tagData = OSCTypeTagArray.kOSCTagTypePrefix.asciiValue else {
            fatalError("Fatal error rending tag data")
        }
        return Data([tagData])
    }()
    
    func tagDescription() throws -> Data {
        guard !isEmpty else {
            throw OSCEncodingError.invalidArgumentList
        }
        
        return reduce(into: OSCTypeTagArray.prefixData) {
            $0.append($1.tagData)
        }.OSCPadded()
    }
    
    static func from(string: String) throws -> OSCTypeTagArray {
        try string.reduce(into: OSCTypeTagArray(capacity: string.count)) {
            if $1 == kOSCTagTypePrefix { return }
            guard let type = OSCDataTypeTag(rawValue: $1) else {
                throw OSCEncodingError.invalidArgumentList
            }
            
            $0.append(type)
        }
    }
}

//MARK: - OSCArgumentArray

typealias OSCArgumentArray = Array<OSCDataType>
extension OSCArgumentArray {
    func typeTags() -> OSCTypeTagArray {
        reduce(into: OSCTypeTagArray(capacity: count)) {
            $0.append($1.tag)
        }
    }
    
    func OSCEncoded() throws -> Data {
        try reduce(into: Data(capacity: count)) {
            $0.append(try $1.OSCEncoded())
        }
    }
    
    static func == (lhs: OSCArgumentArray, rhs: OSCArgumentArray) -> Bool {
        lhs.elementsEqual(rhs) {
            guard $0.tag == $1.tag else {
                return false
            }
            
            do {
                let left = try $0.OSCEncoded()
                let right = try $1.OSCEncoded()
                return left == right
            } catch {
                return false
            }
        }
    }
}

//MARK: - OSCPacketContentsArray

typealias OSCPacketContentsArray = Array<OSCPacketContents>
extension OSCPacketContentsArray {
    func packedContents() throws -> Data {
        try reduce(into: Data(capacity: count)) {
            let packet = try $1.createPacket()
            $0.append(try OSCInt(packet.count).OSCEncoded())
            $0.append(packet)
        }
    }
    
    static func == (lhs: OSCPacketContentsArray, rhs: OSCPacketContentsArray) -> Bool {
        lhs.elementsEqual(rhs) {
            do {
                let left = try $0.createPacket()
                let right = try $1.createPacket()
                return left == right
            } catch {
                return false
            }
        }
    }
}

//MARK: - OSCMethod

//A Method is an object to which a Message is dispatched
// by a OSCNetworkServer based upon a full or partial match
// of its address.
//
// To use: Implement a class of the type OSCMethod
// The handleMessage() function of the OSCMethodProtocol which will
// be called when a message with a full or partial match for the
// address pattern is received.
public protocol OSCMethod: AnyObject {
    var addressPattern: OSCAddressPattern {get set}
    
    func handleMessage(_ message: OSCMessage, for match: OSCPatternMatchType)
}

internal extension OSCMethod {
    func addressMatch(pattern: String) -> OSCPatternMatchType {
        return addressPattern.oscMethodAddressMatch(pattern: pattern)
    }
}

//MARK: - OSCAddressSpace

//I'm cheating a bit and ignoring the level of 'Container' in the design
// of the address space.
//
// The concept of XPath matching in OSC 1.1 breaks the tree structure
// as it potentially requires interrogating all leafs. I have flattened
// the name space rather than special case the XPath search.
//
// Instead I have added the concept of a "container" match
// which indicates a match at the OSC Container level
// were this to be a tree, which it is not.
internal typealias OSCAddressSpace = Array<OSCMethod>
internal extension OSCAddressSpace {
    mutating func register(method: OSCMethod) {
        append(method)
    }
    
    mutating func deregister(method: OSCMethod) {
        removeAll(where: {$0 === method})
    }
    
    func dispatch(packet: OSCPacketContents) {
        switch packet {
        case let message as OSCMessage:
            dispatch(message: message)
            
        case let bundle as OSCBundle:
            bundle.bundleElements?.forEach {
                dispatch(packet: $0)
            }
            
        default:
            fatalError("Unexpected OSCPacketContents")
        }
    }
    
    func dispatch(message: OSCMessage) {
        guard let pattern = message.addressPattern else {
            return
        }
                
        methodsMatching(pattern: pattern).forEach {
            $1.handleMessage(message, for: $0)
        }
    }

    func methodsMatching(pattern: String) -> Array<(OSCPatternMatchType, OSCMethod)> {
        reduce(into: Array<(OSCPatternMatchType, OSCMethod)>()) {
            $0.append(($1.addressMatch(pattern: pattern), $1))
        }.filter {$0.0 != .none}
    }
}

//
//  OSC.swift
//
//
//  Created by Frank Vernon on 6/29/21.
//
// Swift implementation of OSC 1.1
//
//http://opensoundcontrol.org/spec-1_0.html
//http://opensoundcontrol.org/files/2009-NIME-OSC-1.1.pdf

import Foundation

//MARK: - Public

//MARK: - Definitions

public enum OSCCodingError: Error {
    case stringEncodingFailure
    case invalidArgumentList
    case invalidMessage
    case invalidBundle
    case invalidPacket
    case invalidAddress
}

public enum OSCPatternMatchType: Comparable {
    case none
    case container
    case full
}

//MARK: - OSCArgument

public enum OSCArgument: Equatable, Hashable {
    //1.0
    case int(Int32)
    case float(Float32)
    case string(String)
    case blob(Data)
    
    //1.1
    case `true`
    case `false`
    case null
    case impulse
    case timetag(OSCTimeTag)
    
    public init(_ int: Int32) {
        self = .int(int)
    }
    
    public init(_ float: Float32) {
        self = .float(float)
    }
    
    public init(_ string: String) {
        self = .string(string)
    }

    public init(_ blob: Data) {
        self = .blob(blob)
    }
    
    public init(_ bool: Bool) {
        self = bool ? .true : .false
    }
    
    public init(_ timeTag: OSCTimeTag) {
        self = .timetag(timeTag)
    }
    
    public enum TypeTag: Character {
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
    
    public var tag: TypeTag {
        switch self {
        case .int(_):
            return .int
        case .float(_):
            return .float
        case .string(_):
            return .string
        case .blob(_):
            return .blob
        case .true:
            return .true
        case .false:
            return .false
        case .null:
            return .null
        case .impulse:
            return .impulse
        case .timetag(_):
            return .timetag
        }
    }
}

//MARK: - OSCArgumentArray

public typealias OSCArgumentArray = Array<OSCArgument>
extension OSCArgumentArray {
    public func tags() -> OSCArgumentTypeTagArray {
        map { $0.tag }
    }

    public func values(matching tags: OSCArgumentTypeTagArray) throws -> [Any?] {
        guard self.tags() == tags else {
            throw OSCCodingError.invalidArgumentList
        }
        
        return values()
    }
    
    public func values() -> [Any?] {
        map {
            switch $0 {
            case .int(let value):
                return value
            case .float(let value):
                return value
            case .string(let value):
                return value
            case .blob(let value):
                return value
            case .true:
                return true
            case .false:
                return false
            case .null:
                return nil
            case .impulse:
                return OSCArgument.TypeTag.impulse
            case .timetag(let value):
                return value
            }
        }
    }
}

public typealias OSCArgumentTypeTagArray = Array<OSCArgument.TypeTag>

//MARK: - OSCTimeTag

public struct OSCTimeTag: Codable, Equatable, Comparable, Hashable {
    public var seconds: UInt32
    public var picoseconds: UInt32
    
    public var date: Date {
        var interval = TimeInterval(seconds)
        interval += TimeInterval(Double(picoseconds) / 0xffffffff)
        return OSCTimeTag.OSCEpoch.addingTimeInterval(interval)
    }
    
    public var isImmediate: Bool {
        seconds == 0 && picoseconds == 1
    }
    
    public static var immediate: OSCTimeTag = OSCTimeTag(seconds: 0, picoseconds: 1)
    
    public init() {
        self.seconds = 0
        self.picoseconds = 1
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
        //midnight January 1, 1900
        let components = DateComponents(calendar: Calendar(identifier: .gregorian),
                                        year: 1900,
                                        month: 1,
                                        day: 1,
                                        hour: .zero,
                                        minute: .zero,
                                        second: .zero)
        guard let origin = components.date else {
            fatalError("OSC Epoch Date could not be computed")
        }
        
        return origin
    }()
}

//MARK: - OSCAddressPattern

public typealias OSCAddressPattern = String
extension OSCAddressPattern {
    public static let kOSCPartDelim: Character = "/"
    
    //Set of reserved characters for address patterns
    public enum reserved: Character, CaseIterable {
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
    
    public func isValid() -> Bool {
        first == OSCAddressPattern.kOSCPartDelim
            && reserved.reservedCharSet.isDisjoint(with: CharacterSet(charactersIn: self))
    }
}

//MARK: - OSCBundleElement

public protocol OSCBundleElement {
    init(packet: Data) throws
    func packet() throws -> Data
}
public typealias OSCBundleElementArray = Array<OSCBundleElement>

//MARK: - Message

///A Message is a the fundamental unit of information exchange in OSC.
///Messges are comprised of an addressPattern and one or more arguments.
///
///The addressPattern must be a fully qualified or wildcard representation of the address to which to send the message,
///
///The arguments must contain one or more of the well known OSC argument types.
public class OSCMessage: OSCBundleElement {
    public var addressPattern: OSCAddressPattern? = nil
    public var arguments: OSCArgumentArray? = nil
    
    public init() {}
    
    public required init(packet: Data) throws {
        guard let pathRange = packet.nextCStr(after: packet.startIndex),
              let path = String(data: packet[pathRange], encoding: .utf8),
              path.first == "/",
              let tagTypesRange = packet.nextCStr(after: pathRange.endIndex),
              let tagTypes = String(data: packet[tagTypesRange], encoding: .utf8),
              tagTypes.first == "," else {
            throw OSCCodingError.invalidMessage
        }
        
        //get pointer to tag data corresponding to tag type list
        let tagDataOffset = tagTypesRange.endIndex + Data.OSCPadding(for: tagTypesRange.endIndex)
        let tagData = packet[tagDataOffset...]
        var currPos = tagData.startIndex
        
        //parse tag data based on tag type definition
        let types = try OSCArgumentTypeTagArray.from(string: tagTypes)
        let argArray = try types.map { type in
            try OSCArgument(tag: type, data: tagData, at: &currPos)
        }
        
        addressPattern = path
        arguments = argArray
    }

    public convenience init(address: OSCAddressPattern, arguments: OSCArgumentArray) {
        self.init()
        
        self.addressPattern = address
        self.arguments = arguments
    }
    
    public func appendArgument(_ arg: OSCArgument) {
        if arguments == nil {
            arguments = OSCArgumentArray()
        }
        arguments?.append(arg)
    }
    
    ///Returns true if the types (and order) of the arguments in the given array
    /// match the arguments of this message. This is useful for testing whether
    /// a message has the expected arguments before attempting to query
    /// thier values.
    public func argumentsMatch(_ types: OSCArgumentArray) -> Bool {
        return arguments?.tags() == types.tags()
    }
    
    public func packet() throws -> Data {
        guard let address = addressPattern,
              let arguments = arguments else {
            throw OSCCodingError.invalidMessage
        }
        
        var packet = Data()
        packet.append(try address.OSCEncode())
        packet.append(try arguments.OSCEncode())
        
        return packet
    }
}

//MARK: - Bundle

///A Bundle is a collection of Messages and potentially other Bundles.
public class OSCBundle: OSCBundleElement {
    static let kOSCBundleIdentifier = "#bundle"
    static let kOSCBundlePrefix: Character = kOSCBundleIdentifier.first!

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
    
    public func append(element: OSCBundleElement) {
        if elements == nil {
            elements = OSCBundleElementArray()
        }
        elements?.append(element)
    }
    
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

//MARK: - Method

///A Method is an object to which a Message is dispatched
/// based upon a full or partial match of its address.
///
/// To use: Implement a class conforming to OSCMethod with a
/// handleMessage() function which will be called when a message
/// representing a full or partial match for the addressPattern is received.
///
/// - Note: Wildcards are not allowed in Method addressPattern. The
/// addressPattern must be fully qualified and valid.
public protocol OSCMethod: AnyObject {
    var addressPattern: OSCAddressPattern {get set}
    
    func handleMessage(_ message: OSCMessage, for match: OSCPatternMatchType)
}

//MARK: - Equatable

extension OSCBundleElementArray {
    static func == (lhs: OSCBundleElementArray, rhs: OSCBundleElementArray) -> Bool {
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

//MARK: - Internal

//MARK: - OSCArgumentArray

extension OSCArgumentArray {
    func OSCEncode() throws -> Data {
        try reduce(into: try tags().OSCEncode()) {
            $0.append(try $1.encode())
        }
    }
    
    static func == (lhs: OSCArgumentArray, rhs: OSCArgumentArray) -> Bool {
        //do quick check for tags matching to possibly avoid encoding data
        guard lhs.elementsEqual(rhs, by: { $0.tag == $1.tag}) else {
            return false
        }

        return lhs.elementsEqual(rhs) {
            do {
                let left = try $0.encode()
                let right = try $1.encode()
                return left == right
            } catch {
                return false
            }
        }
    }
}

internal extension OSCArgument {
    init(tag: OSCArgument.TypeTag, data: Data, at offset: inout Data.Index) throws {
        switch tag {
        case .int:
            self = .int(try Int32.OSCDecode(data: data, at: &offset))
            
        case .float:
            self = .float(try Float32.OSCDecode(data: data, at: &offset))

        case .string:
            self = .string(try String.OSCDecode(data: data, at: &offset))

        case .blob:
            self = .blob(try Data.OSCDecode(data: data, at: &offset))

        case .true:
            self = .true
            
        case .false:
            self = .false
            
        case .null:
            self = .null
            
        case .impulse:
            self = .impulse
            
        case .timetag:
            self = .timetag(try OSCTimeTag.OSCDecode(data: data, at: &offset))
        }
    }

    func encode() throws -> Data {
        switch self {
        case .int(let value):
            return try value.OSCEncode()
            
        case .float(let value):
            return try value.OSCEncode()

        case .string(let value):
            return try value.OSCEncode()

        case .blob(let value):
            return try value.OSCEncode()

        case .true:
            return Data()
            
        case .false:
            return Data()
            
        case .null:
            return Data()
            
        case .impulse:
            return Data()
            
        case .timetag(let value):
            return try value.OSCEncode()
        }
    }
}

//MARK: - OSCArgumentTag

extension OSCArgumentTypeTagArray {
    fileprivate static var kOSCTagTypePrefix: Character = ","
    fileprivate static var prefixData: Data = {
        guard let tagData = OSCArgumentTypeTagArray.kOSCTagTypePrefix.asciiValue else {
            fatalError("Fatal error rending tag data")
        }
        return Data([tagData])
    }()
    
    func OSCEncode() throws -> Data {
        guard !isEmpty else {
            throw OSCCodingError.invalidArgumentList
        }
        
        return reduce(into: OSCArgumentTypeTagArray.prefixData) {
            guard let intValue: UInt8 = $1.rawValue.asciiValue else {
                fatalError("Fatal error rendering OSC tag data")
            }

            $0.append(intValue)
        }.OSCPadded()
    }
    
    static func from(string: String) throws -> OSCArgumentTypeTagArray {
        try string.reduce(into: OSCArgumentTypeTagArray(capacity: string.count)) {
            if $1 == kOSCTagTypePrefix { return }
            guard let type = OSCArgument.TypeTag(rawValue: $1) else {
                throw OSCCodingError.invalidArgumentList
            }
            
            $0.append(type)
        }
    }
}

//MARK: - OSCCodable

protocol OSCCodable {
    associatedtype T
    
    func OSCEncode() throws -> Data
    static func OSCDecode(data: Data, at offset: inout Data.Index) throws -> T
}

extension Int32: OSCCodable {
    typealias T = Int32
    
    func OSCEncode() throws -> Data {
        var source = self.bigEndian
        return Data(bytes: &source, count: MemoryLayout<Int32>.size)
    }
    
    static func OSCDecode(data: Data, at offset: inout Data.Index) throws -> Int32 {
        guard data.endIndex >= offset + 4 else {
            throw OSCCodingError.invalidMessage
        }
        
        let result = data.subdata(in: offset..<offset + 4).withUnsafeBytes {
            $0.load(as: Int32.self)
        }.bigEndian
        
        offset += 4
        
        return result
    }
}

extension Float32: OSCCodable {
    typealias T = Float32
    
    func OSCEncode() throws -> Data {
        var float: CFSwappedFloat32 = CFConvertFloatHostToSwapped(self)
        let size: Int = MemoryLayout<CFSwappedFloat32>.size
        let result: [UInt8] = withUnsafePointer(to: &float) {
            $0.withMemoryRebound(to: UInt8.self, capacity: size) {
                Array(UnsafeBufferPointer(start: $0, count: size))
            }
        }
        return Data(result)
    }
    
    static func OSCDecode(data: Data, at offset: inout Data.Index) throws -> Float32 {
        guard data.endIndex >= offset + 4 else {
            throw OSCCodingError.invalidMessage
        }
        
        let result = data.subdata(in: offset..<offset + 4).withUnsafeBytes {
            CFConvertFloat32SwappedToHost($0.load(as: CFSwappedFloat32.self))
        }
        
        offset += 4
        
        return result
    }
}

extension String: OSCCodable {
    typealias T = String

    func OSCEncode() throws -> Data {
        guard var data = data(using: .utf8) else {
            throw OSCCodingError.stringEncodingFailure
        }
        
        //append NULL terminator, per spec
        data.append(0)
        data.OSCPad()
        
        return data
    }
    
    static func OSCDecode(data: Data, at offset: inout Data.Index) throws -> String {
        guard let stringRange = data.nextCStr(after: offset),
              let result = String(data: data[stringRange], encoding: .utf8) else {
            throw OSCCodingError.invalidMessage
        }
        offset += stringRange.count + Data.OSCPadding(for: stringRange.count)
        
        return result
    }
}

extension Data: OSCCodable {
    typealias T = Data

    func OSCEncode() throws -> Data {
        var blob = try OSCArgument.int(Int32(count)).encode()
        blob.append(self)
        blob.OSCPad()
        return blob
    }
    
    static func OSCDecode(data: Data, at offset: inout Index) throws -> Data {
        guard data.endIndex >= offset + 4 else {
            throw OSCCodingError.invalidMessage
        }
        
        let blobSize = data.subdata(in: offset..<offset + 4).withUnsafeBytes {
            $0.load(as: Int32.self)
        }.bigEndian
        
        offset += 4

        let endData = offset + Int(blobSize)
        guard endData < data.endIndex else {
            throw OSCCodingError.invalidMessage
        }
        let result = data.subdata(in: offset..<endData)
        
        offset += Int(blobSize) + Data.OSCPadding(for: Int(blobSize))
        
        return result
    }
}

extension OSCTimeTag: OSCCodable {
    typealias T = OSCTimeTag

    func OSCEncode() throws -> Data {
        func encodeUInt32(_ value:UInt32) -> Data {
            var source = value.bigEndian
            return Data(bytes: &source, count: MemoryLayout<UInt32>.size)
        }
        
        var result = encodeUInt32(seconds)
        result.append(encodeUInt32(picoseconds))
        
        return result
    }
    
    static func OSCDecode(data: Data, at offset: inout Data.Index) throws -> OSCTimeTag {
        guard data.endIndex >= offset + 8 else {
            throw OSCCodingError.invalidMessage
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

//MARK: - Address Space

//I'm cheating a bit and ignoring the level of 'Container' in the design
// of the address space.
//
// The concept of XPath matching in OSC 1.1 breaks the tree structure IMHO
// as it potentially requires interrogating all leafs. I have flattened
// the name space rather than special case the XPath search
// across all branches
//
// I have instead added the concept of a "container" match
// which indicates a match at the OSC Container level
// were this to be a tree, which it is not.
internal typealias OSCAddressSpace = Array<OSCMethod>
internal extension OSCAddressSpace {
    mutating func register(methods: [OSCMethod]) throws {
        try methods.forEach {
            try register(method: $0)
        }
    }
    
    mutating func register(method: OSCMethod) throws {
        guard method.addressPattern.isValid() else {
            throw OSCCodingError.invalidAddress
        }
        
        append(method)
    }
    
    mutating func deregister(method: OSCMethod) {
        removeAll(where: {$0 === method})
    }
    
    func dispatch(element: OSCBundleElement) {
        guard !isEmpty else {
            return
        }
        
        switch element {
        case let message as OSCMessage:
            dispatch(message: message)
            
        case let bundle as OSCBundle:
            bundle.elements?.forEach {
                dispatch(element: $0)
            }
            
        default:
            fatalError("Unexpected OSCPacketContents")
        }
    }
    
    func dispatch(message: OSCMessage) {
        guard let pattern = message.addressPattern else {
            return
        }
        
        //TODO: This is an obvious spot to add concurrency, maybe in Swift 5.5
        methodsMatching(pattern: pattern).forEach {
            $1.handleMessage(message, for: $0)
        }
    }
    
    func methodsMatching(pattern: String) -> Array<(OSCPatternMatchType, OSCMethod)> {
        map {
            ($0.addressMatch(pattern: pattern), $0)
        }.filter {$0.0 != .none}
    }
}

internal extension OSCMethod {
    func addressMatch(pattern: String) -> OSCPatternMatchType {
        return addressPattern.oscMethodAddressMatch(pattern: pattern)
    }
}

//This is the meat of the address wildcard pattern matching. It is ugly so I
// have hidden it at the bottom.
extension OSCAddressPattern {
    //Theory of operation...
    //  Walk the pattern and address char by char matching chars based on
    //  rules of the various wildcard elements. Break out of loop
    //  on first occurance of a non-match.
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
            guard let segment = self[addressPos...].range(of: String(OSCAddressPattern.kOSCPartDelim)) else {
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
        
        func patternCharsBetween(start: Character, end: Character) -> Array<Character>? {
            guard currPatternChar() == start else {
                return nil
            }
            
            var charray = Array<Character>()
            while true {
                patternInc()
                
                // if we hit end or end of segment we have an error
                guard let current = currPatternChar(),
                      current != OSCAddressPattern.kOSCPartDelim else {
                    return nil
                }
                
                guard current != end else {
                    patternInc()
                    break
                }
                
                charray.append(current)
            }
            
            return charray
        }
        
        func bracketCharSet() -> (Bool, Array<Character>)? {
            guard var charray = patternCharsBetween(start: "[", end: "]") else {
                return nil
            }
            
            //check for inverted meaning
            var inverted = false
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
            guard let charray = patternCharsBetween(start: "{", end: "}") else {
                return nil
            }
            
            return String(charray).split(separator: ",")
        }
        
        patternLoop: while let patternChar = currPatternChar() {
            let startPattern = patternPos
            switch patternChar {
            case "?": //Match Single
                //match any single char, except segment termination or end of address
                // i.e. there must be at least one more char before
                // the segment termination or end of address:
                // /foo/bar? would match: /foo/bar1, but not /foo/bar/1 or /foo/bar
                guard let current = currAddressChar(),
                      current != OSCAddressPattern.kOSCPartDelim else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }
                
                patternInc()
                addressInc()
                
            case "*": //Match Any
                //match zero or more chars, except segment termination or end of address
                // /foo/bar* would match: /foo/bar1111 or /foo/bar, but not /foo/bar/1111
                patternInc()
                while let current = currAddressChar(),
                      current != OSCAddressPattern.kOSCPartDelim,
                      current != currPatternChar() {
                    addressInc()
                }
                
            case "[": //Match single from range
                //match any single char based on the set of characters expressed in the brackets,
                // except segment termination or end of address
                // i.e. there must be at least one more char before
                // the segment termination or end of address:
                // /foo/bar[1-2] would match: /foo/bar1, but not /foo/bar/1 or /foo/bar
                guard let current = currAddressChar(), current != OSCAddressPattern.kOSCPartDelim,
                      let (inverted, charray) = bracketCharSet(),
                      charray.contains(current) != inverted else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }
                
                //bracketCharSet() increments the patternPos for us
                addressInc()
                
            case "{": //Match string from list
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
                
            case "/": //Path segment termination or XPath wildcard
                //Segment termination or possible start of XPath wildcard
                // regardless check that current address is also starting
                // at segment termination if not bail out
                guard let current = currAddressChar(),
                      current == OSCAddressPattern.kOSCPartDelim else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }
                
                patternInc()
                addressInc()
                
                //check for XPath wildcard in pattern
                if currPatternChar() == OSCAddressPattern.kOSCPartDelim {
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
                        
                        //To understand recursion one must first understand recursion.
                        let match = remainingAddress.oscMethodAddressMatch(pattern: remainingPattern)
                        bestMatch = match > bestMatch ? match : bestMatch
                        if bestMatch == .full {
                            break
                        }
                        
                        guard let nextSegment = self[addressPos...].range(of: String(OSCAddressPattern.kOSCPartDelim)) else {
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
        else if patternPos == pattern.endIndex
                    && currAddressChar() == OSCAddressPattern.kOSCPartDelim {
            return .container
        }
        
        //pattern shorter than address - edge case pattern ends in segment termination
        else if patternPos == pattern.endIndex
                    && (pattern.last == OSCAddressPattern.kOSCPartDelim && prevAddressChar() == OSCAddressPattern.kOSCPartDelim) {
            return .container
        }
        
        return .none
    }
}

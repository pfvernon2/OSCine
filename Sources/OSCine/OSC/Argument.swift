//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/5/21.
//

import Foundation

//MARK: - OSCArgument

///Enum specifying OSC argument types
public enum OSCArgument: Equatable, Hashable {
    case int(Int32)
    case float(Float32)
    case string(String)
    case blob(Data)
    case boolean(Bool)
    case `true`
    case `false`
    case null
    case impulse
    case timetag(OSCTimeTag)
    
    public init(_ int: Int32) { self = .int(int) }
    
    public init(_ float: Float32) { self = .float(float) }
    
    public init(_ string: String) { self = .string(string) }

    public init(_ blob: Data) { self = .blob(blob) }
    
    public init(_ boolean: Bool) { self = .boolean(boolean) }
    
    public init(_ timeTag: OSCTimeTag) { self = .timetag(timeTag) }
}

///Tags for corresponding argument types used in pattern matching
public extension OSCArgument {
    indirect enum TypeTag {
        //exact match
        case int
        case float
        case string
        case blob
        case `true`
        case `false`
        case null
        case impulse
        case timetag
        
        //pattern match
        /// - anyTag: Matches any argument tag
        case anyTag
        
        /// - anyBoolean: Matches any boolean argumment.
        ///
        /// Use `.true` or `.false` to match a specific boolean values.
        case anyBoolean
        
        /// - anyNumber: Matches any numeric argumment.
        ///
        /// Use 'int' or 'float' to match specific numeric types.
        case anyNumber
        
        /// - optional(type): Allows for optional matches of tag types.
        ///
        /// *Important:* Optional tags can only appear at the end of argument type lists.
        case optional(TypeTag)
        
        var isBool: Bool {
            return self == .anyBoolean ||
                self == .true ||
                self == .false
        }
        
        var isNumber: Bool {
            return self == .anyNumber ||
                self == .int ||
                self == .float
        }
    }
    
    ///The type tag for the associated argument
    var tag: TypeTag {
        switch self {
        case .int(_):
            return .int
        case .float(_):
            return .float
        case .string(_):
            return .string
        case .blob(_):
            return .blob
        case .boolean(let value):
            return value ? .true : .false
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

extension OSCArgument.TypeTag: Equatable {
    public func matches(_ other: OSCArgument.TypeTag) -> Bool {
        switch (self, other) {
        case let(left, right) where left == .anyTag || right == .anyTag:
            return true

        case let(left, right) where left == .anyBoolean || right == .anyBoolean:
            return right.isBool && left.isBool

        case let(left, right) where left == .anyNumber || right == .anyNumber:
            return right.isNumber && left.isNumber

        case (.optional(let left), let(right)),
             (let(left), .optional(let right)):
            return left.matches(right)
        
        default:
            return self == other
        }
    }
}

public typealias OSCArgumentTypeTagArray = Array<OSCArgument.TypeTag>

//MARK: - OSCArgumentArray

public typealias OSCArgumentArray = Array<OSCArgument>
extension OSCArgumentArray {
    public func tags() -> OSCArgumentTypeTagArray {
        map { $0.tag }
    }
    
    ///Returns heterogenous array of values only if they match the given array of type tags.
    ///This is useful to validate arguments and retrieve their values in a single step.
    public func values(matching pattern: OSCArgumentTypeTagArray) -> [Any?]? {
        guard matches(pattern: pattern) else {
            return nil
        }
        
        return values()
    }
    
    ///Returns all values of the arguments as heterogenous array
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
            case .boolean(let value):
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
    
    ///Check if the given type tag pattern matches the array of arguments
    public func matches(pattern: OSCArgumentTypeTagArray) -> Bool {
        let argTags = tags()
        
        //quick check: ensure we have at least as many pattern elements (some of which may be optional)
        // as we have argument elements
        guard pattern.count >= argTags.count else {
            return false
        }
        
        //check if we have trailing optionals in the pattern…
        // if not just compare all as required elements
        guard let firstOptional = pattern.firstIndexOfOptional() else {
            return argTags.elementsEqual(pattern) { $0.matches($1) }
        }
        
        //check required tags, i.e. all tags up to the trailing optionals
        let requiredArgs = argTags[..<Swift.min(firstOptional, argTags.endIndex)]
        let requiredPattern = pattern[..<firstOptional]
        guard requiredArgs.elementsEqual(requiredPattern, by: {$0.matches($1)}) else {
            return false
        }
        
        //check we have only optionals in the tail
        guard !pattern[firstOptional...].contains(where: {
            guard case .optional(_) = $0 else { return true }
            return false
        }) else {
            return false
        }

        //compare optionals up to the number of remaining args…
        // optionals past the end can be assumed to match
        let patternOptionals = pattern[firstOptional..<argTags.endIndex]
        let argOptionals = argTags[firstOptional...]
        return argOptionals.elementsEqual(patternOptionals) { $0.matches($1) }
    }
}

//MARK: - OSCTimeTag

///OSC TimeTag argument
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

//MARK: - Internal

//MARK: - OSCCodable

//Internal protocol for encoding and decoding of OSC argument types in messages.
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

//MARK: - OSCArgument internal

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
            self = .boolean(true)
            
        case .false:
            self = .boolean(false)

        case .null:
            self = .null
            
        case .impulse:
            self = .impulse
            
        case .timetag:
            self = .timetag(try OSCTimeTag.OSCDecode(data: data, at: &offset))
            
        default:
            throw OSCCodingError.invalidArgumentList
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

        case .boolean(_), .true, .false, .null, .impulse:
            return Data()

        case .timetag(let value):
            return try value.OSCEncode()
        }
    }
}

//MARK: - OSCArgumentArray internal

extension OSCArgumentArray {
    func OSCEncode() throws -> Data {
        try reduce(into: try tags().OSCEncode()) {
            $0.append(try $1.encode())
        }
    }
    
    static func == (lhs: OSCArgumentArray, rhs: OSCArgumentArray) -> Bool {
        print(lhs, rhs)
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

//MARK: - OSCArgument.TypeTag internal

//Extension to map OSC type tag characters to/from enum
extension OSCArgument.TypeTag {
    fileprivate static var OSCTypeTagCharacters: Array<Character> {
        ["i", "f", "s", "b", "T", "F", "N", "I", "T"]
    }
    fileprivate static var ArgumentCases: [OSCArgument.TypeTag] {
        [.int, .float, .string, .blob, .true, .false, .null, .impulse, .timetag]
    }
    
    var asciiValue : UInt8? {
        guard let index = Self.ArgumentCases.firstIndex(of: self) else {
            return nil
        }
        return Self.OSCTypeTagCharacters[index].asciiValue
    }
    
    init?(char: Character) {
        guard let index = Self.OSCTypeTagCharacters.firstIndex(of: char) else {
            return nil
        }
        self = Self.ArgumentCases[index]
    }
}

//MARK: - OSCArgumentTypeTagArray internal

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
            guard let intValue: UInt8 = $1.asciiValue else {
                fatalError("Fatal error rendering OSC tag data")
            }

            $0.append(intValue)
        }.OSCPadded()
    }
    
    static func from(string: String) throws -> OSCArgumentTypeTagArray {
        try string.reduce(into: OSCArgumentTypeTagArray(capacity: string.count)) {
            if $1 == kOSCTagTypePrefix { return }
            guard let type = OSCArgument.TypeTag(char: $1) else {
                throw OSCCodingError.invalidArgumentList
            }
            
            $0.append(type)
        }
    }
    
    func firstIndexOfOptional() -> Self.Index? {
        firstIndex {
            guard case .optional(_) = $0 else { return false }
            return true
        }
    }
}

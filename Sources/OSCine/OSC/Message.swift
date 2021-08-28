//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/5/21.
//

import Foundation

//MARK: - Message

///A Message is the fundamental unit of information exchange in OSC.
///Messges are comprised of an `Address Pattern` and one or more `Arguments`.
///
///The address pattern represents the address of one or more `Methods` in the `Address Space`
///of the `Server` to which you are sending the `Message`. It may be either a fully qualified address,
///a wildcard representation of one or more addresses, or a partial `Container` match for an address.
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

    public convenience init(addressPattern: OSCAddressPattern, arguments: OSCArgumentArray) {
        self.init()
        
        self.addressPattern = addressPattern
        self.arguments = arguments
    }
    
    ///Adds an argument to the end of the array of arguments for this message
    public func appendArgument(_ arg: OSCArgument) {
        if arguments == nil {
            arguments = OSCArgumentArray()
        }
        arguments?.append(arg)
    }
    
    ///Returns true if the types and order of the arguments in the type tag array
    /// match the arguments of this message. This is useful for testing whether
    /// a message has the expected arguments before attempting to query
    /// for values.
    public func argumentsMatch(_ pattern: OSCArgumentTypeTagArray) -> Bool {
        guard let arguments = arguments else {
            return false
        }
        
        return arguments.matches(pattern: pattern)
    }
    
    ///Returns an OSC encoded representation of the message suitable for
    /// transmission to a server.
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

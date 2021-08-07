//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/5/21.
//

import Foundation

//MARK: - Method

///A Method is an object to which a Message is dispatched via the AddressSpace
/// based upon a full or partial match of its address.
///
/// Implement a class conforming to OSCMethod with a
/// handleMessage() function which will be called when a message
/// representing a full or partial match for the addressPattern is received.
/// If the optional requiredArguments is supplied this will be used by the
/// AddressSpace to filter messages which do not match the required pattern
/// of arguments.
///
/// - Note: Wildcards are not allowed in a Methods addressPattern. The
/// addressPattern must be fully qualified and valid.
public protocol OSCMethod: AnyObject {
    var addressPattern: OSCAddressPattern {get set}
    var requiredArguments: OSCArgumentTypeTagArray? {get set}
    
    func handleMessage(_ message: OSCMessage, for match: OSCPatternMatchType)
}

public extension OSCMethod {
    func addressMatch(pattern: String) -> OSCPatternMatchType {
        addressPattern.match(pattern: pattern)
    }

    func hasRequiredArguments(message: OSCMessage) -> Bool {
        guard let requiredArguments = requiredArguments else {
            return true
        }

        return message.argumentsMatch(requiredArguments)
    }
    
    var description: String {
        "\(addressPattern),\(requiredArguments != nil ? requiredArguments! : [])"
    }
}

//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/5/21.
//

import Foundation

//MARK: - Method

///OSC defines a `Method` as an entity to which a `Message` is dispatched via the `Address Space`
/// based upon a full or partial match of its address.
///
///# Usage #
///
/// Implement a class conforming to OSCMethod with a `handleMessage()` function and `OSCAddressPattern`.
/// The `handleMessage()` function will be called when a message representing a full or partial match for
/// the `OSCAddressPattern` is received.
///
/// If the optional `OSCArgumentTypeTagArray` is supplied it will be used
/// to further filter messages which do not contain the specified pattern
/// of arguments for the given `OSCAddressPattern`.
///
/// - Note: Wildcards are not allowed in a Methods addressPattern. The
/// addressPattern must be fully qualified and valid.
public protocol OSCMethod: AnyObject {
    var addressPattern: OSCAddressPattern {get set}
    var requiredArguments: OSCArgumentTypeTagArray? {get set}
    
    ///This method is called when a full or partial match is made for the address pattern
    /// and (optional) required arguments. If the `Message` was part of a `Bundle` the
    /// `Time Tag` for that bundle is passed as well.
    func handleMessage(_ message: OSCMessage,
                       for match: OSCPatternMatchType,
                       at timeTag: OSCTimeTag?)
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

//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/5/21.
//

import Foundation

//MARK: - Address Space

///The collection of Methods to which Messages are dispatched based on
///full or partial matches of thier Address Patterns.
///
/// - note:
///I'm cheating a bit and ignoring the level of 'Container' in the design
/// of this address space.
///
/// The concept of XPath matching in OSC 1.1 invalidates the recommended tree structure, IMHO,
/// as it potentially requires interrogating all leafs. I have flattened
/// the name space rather than special case the XPath search
/// across all branches.
///
/// Instead I have added the concept of a "container" match
/// which indicates a match at the OSC Container level
/// were this to be a tree, which it is not. See: `OSCPatternMatchType`
public typealias OSCAddressSpace = Array<OSCMethod>
public extension OSCAddressSpace {
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
    
    func dispatch(element: OSCBundleElement, at timetag: OSCTimeTag? = nil) {
        guard !isEmpty else {
            return
        }
        
        switch element {
        case let message as OSCMessage:
            dispatch(message: message, at: timetag)
            
        case let bundle as OSCBundle:
            bundle.elements?.forEach {
                dispatch(element: $0, at: bundle.timeTag)
            }
            
        default:
            fatalError("Unexpected OSCBundleElement")
        }
    }
    
    func dispatch(message: OSCMessage, at timetag: OSCTimeTag? = nil) {
        guard let pattern = message.addressPattern else {
            return
        }
        
        //TODO: This is an obvious spot to add concurrency, maybe in Swift 5.5
        methodsMatching(pattern: pattern).forEach {
            guard $1.hasRequiredArguments(message: message) else {
                return
            }

            $1.handleMessage(message, for: $0, at: timetag)
        }
    }
    
    func methodsMatching(pattern: String) -> Array<(OSCPatternMatchType, OSCMethod)> {
        map {
            ($0.addressMatch(pattern: pattern), $0)
        }.filter {$0.0 != .none}
    }
    
    var methodDescriptions: [String] {
        map { $0.description }
    }
}

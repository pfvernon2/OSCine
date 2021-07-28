//
//  SLIP.swift
//  
//
//  Created by Frank Vernon on 6/30/21.
//
// https://datatracker.ietf.org/doc/html/rfc1055

import Foundation
import Network

//MARK: - Definitions

enum SLIPProtocolError: Error {
    case encodingFailure
    case decodingFailure
}

enum SLIPCodes: UInt8 {
    case END = 0o0300
    case ESC = 0o0333
    case ESC_END = 0o0334
    case ESC_ESC = 0o0335
}

extension SLIPCodes {
    //Characters needing escape sequences
    static var escapedChars: [UInt8] {
        [SLIPCodes.END.rawValue, SLIPCodes.ESC.rawValue]
    }
    
    //Escape sequence for end char
    static var endEscape: Data {
        Data([SLIPCodes.ESC.rawValue, SLIPCodes.ESC_END.rawValue])
    }
    
    //Escape sequence for esc char
    static var escEscape: Data {
        Data([SLIPCodes.ESC.rawValue, SLIPCodes.ESC_ESC.rawValue])
    }
    
    //Datagram termination sequence
    static var end: Data {
        Data([SLIPCodes.END.rawValue])
    }
    
    //Datagram escape initiation
    static var esc: Data {
        Data([SLIPCodes.ESC.rawValue])
    }
}

//MARK: - Data Extension

//Data extension for conversion to/from SLIP for direct serialization of data in memory
extension Data {
    //Returns copy of data with SLIP encoding applied
    // Assumes data is single datagram
    func SLIPEncoded() -> Data {
        var result = Data(self)
        result.SLIPEncode()
        return result
    }

    //Applies SLIP encoding in place on current data
    // Assumes data is single datagram
    mutating func SLIPEncode() {
        //walk data looking for characters requiring escape and replace with escape sequence
        var nextOffset = startIndex
        while let escIndex = self[nextOffset...].firstIndex(where: { SLIPCodes.escapedChars.contains($0) }) {
            guard let slipEsc = SLIPCodes(rawValue: self[escIndex]) else {
                fatalError("SLIP encode failure")
            }
            
            switch slipEsc {
            case SLIPCodes.END:
                replaceSubrange(escIndex...escIndex, with: SLIPCodes.endEscape)
                nextOffset = escIndex + SLIPCodes.endEscape.count
                
            case SLIPCodes.ESC:
                replaceSubrange(escIndex...escIndex, with: SLIPCodes.escEscape)
                nextOffset = escIndex + SLIPCodes.escEscape.count
                
            default:
                fatalError("SLIP encode failure")
            }
        }
        
        append(SLIPCodes.end)
    }
    
    //Returns copy of data with SLIP encoding removed
    func SLIPDecoded() throws -> Data {
        var result = Data(self)
        try result.SLIPDecode()
        return result
    }
    
    //Remove SLIP encoding in place on current data
    mutating func SLIPDecode() throws {
        //check for END at end... before decode
        if last == SLIPCodes.END.rawValue {
            removeLast()
        }

        //walk data looking for escape sequences and replacing with unescaped values
        var currentPos: Int = startIndex
        while let nextEscape = range(of: SLIPCodes.esc, options:[], in: currentPos..<endIndex) {
            guard nextEscape.startIndex + 1 < endIndex else {
                throw SLIPProtocolError.decodingFailure
            }
            
            switch self[nextEscape.startIndex + 1] {
            case SLIPCodes.ESC_END.rawValue:
                replaceSubrange(nextEscape.startIndex...nextEscape.startIndex + 1, with: SLIPCodes.end)
                
            case SLIPCodes.ESC_ESC.rawValue:
                replaceSubrange(nextEscape.startIndex...nextEscape.startIndex + 1, with: SLIPCodes.esc)
                
            default:
                throw SLIPProtocolError.decodingFailure
            }
            currentPos = nextEscape.startIndex + 1
        }
    }
}

//MARK: - Protocol Framer

//Protocol Framer Implementation of SLIP Protocol
class SLIPProtocol: NWProtocolFramerImplementation {
    static let definition = NWProtocolFramer.Definition(implementation: SLIPProtocol.self)
    static var label: String { "SLIP" }
    
    required init(framer: NWProtocolFramer.Instance) {}
    
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
        
    func wakeup(framer: NWProtocolFramer.Instance) {}
    
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    
    func cleanup(framer: NWProtocolFramer.Instance) {}
        
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var parsedDatagram: Data? = nil
            let parsed = framer.parseInput(minimumIncompleteLength: 1,
                                           maximumLength: Int.max) { (buffer, isComplete) -> Int in
                //Confirm we have a buffer and that it contains at least one datagram terminator
                //This is kind of cheating but testing for partial SLIP escape sequences complicated things unnecessarily
                // as we need the complete packet before data is delivered up the stack
                guard let buffer = buffer, let datagramTerminator = buffer.firstIndex(of: SLIPCodes.END.rawValue) else {
                    //many/most datagrams will be short so ask for more data as quickly as available
                    return .zero
                }

                //copy data and remove SLIP encoding
                do {
                    let datagram = Data(buffer[buffer.startIndex...datagramTerminator])
                    parsedDatagram = try datagram.SLIPDecoded()
                } catch {
                    OSCNetworkLogger.error("SLIPProtocol message decode failure: \(error.localizedDescription)")
                }
                
                //even if we fail parsing return data as consumed since we can't process it
                //this will drop the message
                return datagramTerminator + 1
            }
            
            guard parsed else {
                return .zero
            }
            
            if let parsedDatagram = parsedDatagram {
                framer.deliverInput(data: parsedDatagram,
                                    message: NWProtocolFramer.Message(definition: SLIPProtocol.definition),
                                    isComplete: true)
            }
        }
    }
    
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        //Loop
        // Send available data up to characater needing escape, Send escape sequence, Rinse, Repeat
        while true {
            let more = framer.parseOutput(minimumIncompleteLength: 1, maximumLength: Int.max) { unsafePointer, complete in
                guard let unsafePointer = unsafePointer, unsafePointer.count > .zero else {
                    return .zero
                }
                
                do {
                    //find next char needing escape
                    if let esc = unsafePointer.firstIndex(where: { SLIPCodes.escapedChars.contains($0) }) {
                        guard let slipEsc = SLIPCodes(rawValue: unsafePointer[esc]) else {
                            fatalError("SLIP encode failure")
                        }

                        //write up to, but not including, the character needing escape
                        try framer.writeOutputNoCopy(length: esc)
                        
                        //send the escape sequence for the char needing escape
                        switch slipEsc {
                        case SLIPCodes.END:
                            framer.writeOutput(data: SLIPCodes.endEscape)

                        case SLIPCodes.ESC:
                            framer.writeOutput(data: SLIPCodes.escEscape)

                        default:
                            break
                        }

                        //skip over encoded char on next iteration
                        return 1
                    } else {
                        //nothing to escpape - send this entire portion of the message
                        try framer.writeOutputNoCopy(length: unsafePointer.count)
                        return .zero
                    }
                } catch {
                    OSCNetworkLogger.error("SLIPProtocol message encode failure: \(error.localizedDescription)")
                    return .zero
                }
            }
            
            if !more {
                break
            }
        }
        
        //If this is end of message, write SLIP terminator
        if isComplete {
            framer.writeOutput(data: SLIPCodes.end)
        }
    }
}

extension NWProtocolFramer.Message {
    convenience init(message: OSCMessage) {
        self.init(definition: SLIPProtocol.definition)
    }
}

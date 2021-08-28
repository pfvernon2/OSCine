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

///Enum specifying matches between OSCAddressPattern objects
public enum OSCPatternMatchType: Comparable {
    /// - none: No corresponding match between address patterns
    case none
    
    /// - container: "Container" match as defined in OSC
    /// This is a partial match of address pattern up to  a path delimiter
    case container
    
    /// - full: A complete match of the two address paths
    case full
}

//MARK: - OSCAddressPattern

///A string representation of the address pattern.
///
///This might be a fully qualified path to a method, a partial path to a method (i.e. a "continer"),
///or a wildcard representation of a path to a method.
public typealias OSCAddressPattern = String
extension OSCAddressPattern {
    public static let kOSCPartDelim: Character = "/"
    
    ///Set of reserved characters for address patterns
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
    
    ///Check for leading part delim and ensure no reserved chars used
    public func isValid() -> Bool {
        first == OSCAddressPattern.kOSCPartDelim
            && reserved.reservedCharSet.isDisjoint(with: CharacterSet(charactersIn: self))
    }
}

//This is the meat of the address wildcard pattern matching. Sorry it is so ugly,
// but it's complicated and I wanted to make it easy to support later.
extension OSCAddressPattern {
    ///Matches address patterns including those with wildcard evaluations.
    ///
    /// - parameter pattern: An address pattern to compare against.
    /// - returns: Pattern match type, see: OSCPatternMatchType
    public func match(pattern: String) -> OSCPatternMatchType {
        var addressPos = startIndex
        var patternPos = pattern.startIndex
        
        ///increment address position
        func addressInc(_ count: Int = 1) {
            //note: this is potentially unsafe - may walk past end
            // but we are in theory protected by logic used below
            addressPos = index(addressPos, offsetBy: count)
        }
        
        ///address char at current position
        func currAddressChar() -> Character? {
            addressPos < endIndex ? self[addressPos] : nil
        }
        
        ///remainder of address segment up to part delimiter
        func currAddressSegment() -> Substring {
            guard let segment = self[addressPos...].range(of: String(OSCAddressPattern.kOSCPartDelim)) else {
                return self[addressPos...]
            }
            return self[addressPos..<segment.lowerBound]
        }
        
        ///address char before current position
        func prevAddressChar() -> Character? {
            guard addressPos > startIndex else {
                return nil
            }
            return self[index(addressPos, offsetBy: -1)]
        }
        
        ///increment pattern position
        func patternInc() {
            patternPos = pattern.index(after: patternPos)
        }
        
        ///pattern char at current position
        func currPatternChar() -> Character? {
            patternPos < pattern.endIndex ? pattern[patternPos] : nil
        }
        
        ///range of pattern chars... used to extract wildcard sequences
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
        
        ///parse pattern chars between brackets and potentially expand ranges
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
        
        ///parse pattern string sets
        func parenStringSet() -> [Self.SubSequence]? {
            guard let charray = patternCharsBetween(start: "{", end: "}") else {
                return nil
            }
            
            return String(charray).split(separator: ",")
        }
        
        //Theory of operation...
        //  Walk both the pattern and address matching chars based on
        //  rules of the various wildcard elements. Break out of loop
        //  on first occurance of a non-match.
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
                // /foo/bar* would match: /foo/bar or /foo/bar1111, but not /foo/bar/1111
                patternInc()
                while let current = currAddressChar(),
                      current != OSCAddressPattern.kOSCPartDelim,
                      current != currPatternChar() {
                    addressInc()
                }
                
            case "[": //Match any from set or range of chars
                //match zero or more chars based on the set of characters expressed within the brackets,
                // except segment termination or end of address
                // /foo/bar[0-9] would match: /foo/bar1 and /foo/bar12 or /foo/bar, but not /foo/bar/1
                guard let (inverted, charray) = bracketCharSet() else {
                    addressPos = endIndex
                    patternPos = startPattern
                    break patternLoop
                }
                
                while let current = currAddressChar(),
                      current != OSCAddressPattern.kOSCPartDelim,
                      current != currPatternChar(),
                      charray.contains(current) != inverted {
                    addressInc()
                }

                //bracketCharSet() increments the patternPos for us
                
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
                        let match = remainingAddress.match(pattern: remainingPattern)
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
                //match address and pattern characters
                guard let addrChar = currAddressChar(),
                      let patternChar = currPatternChar(),
                      addrChar == patternChar else {
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

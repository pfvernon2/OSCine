import Network

import XCTest
@testable import OSCine

let mcastAddressEndpoint: NWEndpoint = .hostPort(host: "239.65.11.3", port: 65113)

let message = OSCMessage(addressPattern: "/i/T/f/F",
                         arguments:[
                            .int(1),
                            .true,
                            .float(2.0),
                            .boolean(false)
                         ])
let messageHex = "2F692F542F662F46000000002C695466460000000000000140000000"

let datagram = Data([10, SLIPEscapeCodes.END.rawValue,
                     20, 21, SLIPEscapeCodes.ESC.rawValue, SLIPEscapeCodes.ESC.rawValue,
                     30, 31, 32, SLIPEscapeCodes.END.rawValue])
let SLIPDatagram = Data([10, SLIPEscapeCodes.ESC.rawValue, SLIPEscapeCodes.ESC_END.rawValue,
                         20, 21, SLIPEscapeCodes.ESC.rawValue, SLIPEscapeCodes.ESC_ESC.rawValue, SLIPEscapeCodes.ESC.rawValue, SLIPEscapeCodes.ESC_ESC.rawValue,
                         30, 31, 32, SLIPEscapeCodes.ESC.rawValue, SLIPEscapeCodes.ESC_END.rawValue, SLIPEscapeCodes.END.rawValue])

let OSCTestServiceName = "OSCine_Test"

var testMessages: [OSCMessage] = {
    let message1 = OSCMessage(addressPattern: "/test/mixer/*/knob[0-9]",
                              arguments: [.float(0.75)])
    
    let message2 = OSCMessage(addressPattern: "/test/mixer/*/slider?",
                              arguments: [.float(0.75)])
    
    let message3 = OSCMessage(addressPattern: "/test/mixer/*/button*",
                              arguments: [.int(1), .int(0)])
    
    let message4 = OSCMessage(addressPattern: "/test/mixer/*/{label1,label2}",
                              arguments: [.string("This is a test")])
    
    let message5 = OSCMessage(addressPattern: "//master",
                              arguments: [.true])
    
    let message6 = OSCMessage(addressPattern: "//blob",
                              arguments: [.blob(datagram)])
    
    return [message1, message2, message3, message4, message5, message6]
}()

var testBundle: OSCBundle = {
    return OSCBundle(timeTag: OSCTimeTag.immediate,
                     elements: testMessages)
}()

var testMethods: [MethodTest] = {
    var result = [MethodTest](capacity: 5)
    result.append(MethodTest(address: "/test/mixer/1/knob8", requiredArguments: [.float]))
    result.append(MethodTest(address: "/test/mixer/1/slider1"))
    result.append(MethodTest(address: "/test/mixer/1/button3", requiredArguments: [.int, .optional(.int)]))
    result.append(MethodTest(address: "/test/mixer/1/label1", requiredArguments: [.string]))
    result.append(MethodTest(address: "/test/mixer/1/master/eq1/bypass", requiredArguments: [.anyBoolean]))
    result.append(MethodTest(address: "/test/mixer/1/blob/data", requiredArguments: [.blob]))
    return result
}()

final class OSCineTests: XCTestCase {
    func testoscMethodAddressMatching() {
        //Test ?
        let path1 = "/foobar/foo/bar"
        let path1_full = "/foobar/fo?/bar"
        let path1_none = "/foobar/foo?/bar"
        let path1_container = "/foobar/fo?"
        let path1_container2 = "/foobar/fo?/"
        let path1_none_end = "/foobar/foo/bar?"
        XCTAssert(path1.isValid())
        XCTAssert(!path1_full.isValid())
        XCTAssert(path1.match(pattern: path1_full) == .full)
        XCTAssert(path1.match(pattern: path1_none) == .none)
        XCTAssert(path1.match(pattern: path1_container) == .container)
        XCTAssert(path1.match(pattern: path1_container2) == .container)
        XCTAssert(path1.match(pattern: path1_none_end) == .none)
        
        //Test *
        let path2 = "/foobar/fooo/bar"
        let path2_full = "/foobar/fo*/b*r"
        let path2_none = "/foobar/foooo*/bar"
        let path2_container = "/foobar/fooo*"
        let path2_none_end = "/foobar/f*/bar/1*"
        XCTAssert(path2.isValid())
        XCTAssert(!path2_full.isValid())
        XCTAssert(path2.match(pattern: path2_full) == .full)
        XCTAssert(path2.match(pattern: path2_none) == .none)
        XCTAssert(path2.match(pattern: path2_container) == .container)
        XCTAssert(path2.match(pattern: path2_none_end) == .none)
        
        //Test ? and *
        let path3 = "/foobar/foo1/bar"
        let path3_full = "/foobar/foo?/b*r"
        let path3_none = "/foobar/foo1?/b*r"
        let path3_container = "/foobar/f?*"
        let path3_none_end = "/foobar/foo?/ba"
        XCTAssert(path3.isValid())
        XCTAssert(!path3_full.isValid())
        XCTAssert(path3.match(pattern: path3_full) == .full)
        XCTAssert(path3.match(pattern: path3_none) == .none)
        XCTAssert(path3.match(pattern: path3_container) == .container)
        XCTAssert(path3.match(pattern: path3_none_end) == .none)
        
        //Test []
        let path4 = "/foobar/foo123/bar"
        let path4_full = "/foobar/foo[a-z0-9]/ba[a-z]"
        let path4_full2 = "/foobar/foo1[a-z0-9]/bar"
        let path4_container = "/foobar/fo?[a-z0-9]"
        let path4_none_end = "/foobar/foo?/ba[0-9]"
        XCTAssert(path4.isValid())
        XCTAssert(!path4_full.isValid())
        XCTAssert(path4.match(pattern: path4_full) == .full)
        XCTAssert(path4.match(pattern: path4_full2) == .full)
        XCTAssert(path4.match(pattern: path4_container) == .container)
        XCTAssert(path4.match(pattern: path4_none_end) == .none)
        
        //Test {}
        let path5 = "/foobar/foo1/bar"
        let path5_full = "/foobar/{foo,foo1}/bar"
        let path5_none = "/foobar/{oof,oof1}/bar"
        let path5_container = "/foobar/{foo,foo1}"
        let path5_none_end = "/foobar/foo?/{rab,rab1}"
        XCTAssert(path5.isValid())
        XCTAssert(!path5_full.isValid())
        XCTAssert(path5.match(pattern: path5_full) == .full)
        XCTAssert(path5.match(pattern: path5_none) == .none)
        XCTAssert(path5.match(pattern: path5_container) == .container)
        XCTAssert(path5.match(pattern: path5_none_end) == .none)
        
        //Test //
        let path6 = "/foobar/foo1/bar"
        let path6_full = "/foobar//b?r"
        let path6_full2 = "//foo[0-9]/b?r*"
        let path6_none = "/foobar//foo[0-9]/b?r/1111"
        let path6_container = "//foobar/{foo,foo1}"
        let path6_none_end = "//bar1"
        XCTAssert(path6.isValid())
        XCTAssert(!path6_full.isValid())
        XCTAssert(path6.match(pattern: path6_full) == .full)
        XCTAssert(path6.match(pattern: path6_full2) == .full)
        XCTAssert(path6.match(pattern: path6_none) == .none)
        XCTAssert(path6.match(pattern: path6_container) == .container)
        XCTAssert(path6.match(pattern: path6_none_end) == .none)
    }
    
    func testSLIPEncodeDecode() {
        do {
            //test encode/decode of datagram
            let encoded = datagram.SLIPEncoded()
            XCTAssertEqual(encoded, SLIPDatagram)
            
            let decoded = try encoded.SLIPDecoded()
            XCTAssertEqual(decoded, datagram)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testMessageEncodeDecode() {
        do {
            //convert message to datagram and compare to hand calculated data set
            let packet = try message.packet()
            XCTAssertEqual(packet.hexRepresentation(), messageHex)
            
            //convert datagram back to message and confirm it matches original
            let packetMessage = try OSCMessage(packet: packet)
            XCTAssertEqual(packetMessage, message)
            
            //Test encode/decode of bundle
            let bundlePacket = try testBundle.packet()
            let bundleEncoded = bundlePacket.SLIPEncoded()
            let bundleDecoded = try bundleEncoded.SLIPDecoded()
            XCTAssertEqual(bundlePacket, bundleDecoded)
        } catch {
            testPrint(#function, error, prefix: String.boom)
            XCTFail(error.localizedDescription)
        }
    }
    
    func testArgumentPatternMatching() {
        let args: OSCArgumentArray = [.float(1.0), .int(1), .boolean(true), .impulse]
        
        let pattern: OSCArgumentTypeTagArray = [.float, .int, .true]
        XCTAssert(!args.matches(pattern: pattern))

        let pattern1: OSCArgumentTypeTagArray = [.anyNumber, .int, .anyBoolean, .impulse]
        XCTAssert(args.matches(pattern: pattern1))

        let pattern2: OSCArgumentTypeTagArray = [.float, .anyNumber, .anyBoolean, .optional(.impulse)]
        XCTAssert(args.matches(pattern: pattern2))

        let pattern3: OSCArgumentTypeTagArray = [.float, .anyTag, .true, .optional(.anyTag)]
        XCTAssert(args.matches(pattern: pattern3))

        let pattern4: OSCArgumentTypeTagArray = [.float, .anyTag, .true, .optional(.anyTag), .optional(.anyNumber)]
        XCTAssert(args.matches(pattern: pattern4))

        let pattern5: OSCArgumentTypeTagArray = [.float, .anyTag, .true, .impulse, .optional(.anyNumber), .optional(.anyTag)]
        XCTAssert(args.matches(pattern: pattern5))

        let pattern6: OSCArgumentTypeTagArray = [.optional(.anyNumber), .anyTag, .true, .impulse, .optional(.anyNumber), .optional(.anyTag)]
        XCTAssert(!args.matches(pattern: pattern6))

        let pattern7: OSCArgumentTypeTagArray = [.float, .null, .true, .anyTag]
        XCTAssert(!args.matches(pattern: pattern7))
        
        let pattern8: OSCArgumentTypeTagArray = [.float, .anyTag, .true, .impulse, .impulse, .optional(.anyNumber), .optional(.anyTag)]
        XCTAssert(!args.matches(pattern: pattern8))
    }
    
    let server = ServerTest()
    let client = ClientTest()
    func testServerAnnoucementClientUDP() {
        testPrint("Starting UDP Server - Annoucement - Client Test")
        
        let serverExp = expectation(description: "\(#function)")
        serverExp.expectedFulfillmentCount = testBundle.elements?.count ?? .zero
        server.runTest(expectation: serverExp)
        
        let clientExp = expectation(description: "\(#function)")
        client.runTest(expectation: clientExp)
        
        wait(for: [serverExp, clientExp], timeout: 30.0, enforceOrder: false)
        
        server.server.cancel()
    }
    
    func testServerAnnoucementClientTCP() {
        testPrint("Starting TCP Server - Annoucement - Client Test")
        
        let serverExp = expectation(description: "\(#function)")
        serverExp.expectedFulfillmentCount = testBundle.elements?.count ?? Int.max
        server.runTest(expectation: serverExp, useTCP: true)
        
        let clientExp = expectation(description: "\(#function)")
        self.client.runTest(expectation: clientExp, useTCP: true)
        
        wait(for: [serverExp, clientExp], timeout: 30.0, enforceOrder: false)
        
        server.server.cancel()
    }
    
    let mcast = MulticastTest()
    func testMulticast() {
        testPrint("Starting Multicast Test")
        
        let exp = expectation(description: "\(#function)")
        exp.expectedFulfillmentCount = testMessages.count * 2
        
        mcast.runTest(expectation: exp)
        
        wait(for: [exp], timeout: 30.0, enforceOrder: false)
    }
}

class ClientTest: OSCClientDelegate {
    lazy var udpClient: OSCClientUDP = {
        let client = OSCClientUDP()
        client.delegate = self
        return client
    }()
    
    lazy var tcpClient: OSCClientTCP = {
        let client = OSCClientTCP()
        client.delegate = self
        return client
    }()
    
    var useTCP: Bool = false
    var client: OSCClient {
        useTCP ? tcpClient : udpClient
    }
    
    var expectation: XCTestExpectation? = nil
    
    func runTest(expectation: XCTestExpectation, useTCP: Bool = false) {
        self.expectation = expectation
        self.useTCP = useTCP
        
        testPrint("Client intiating browse for service")
        client.connect(serviceName: OSCTestServiceName, timeout: 10.0)
    }
    
    //OSCClientDelegate
    func connectionStateChange(_ state: NWConnection.State) {
        switch state {
        case .failed(let error):
            XCTFail(error.localizedDescription)
            expectation?.fulfill()
            
        case .ready:
            testPrint("Client ready, sending message")
            sendMessage()
            
        default:
            testPrint("Client state changed: \(state)")
            break
        }
    }
    
    func sendMessage() {
        do {
            try client.send(testBundle) { error in
                testPrint("Client bundle sent: \(error?.debugDescription ?? "success!")")
                self.client.disconnect()
                self.expectation?.fulfill()
            }
        } catch {
            testPrint(#function, error, prefix: String.boom)
            XCTFail(error.localizedDescription)
        }
    }
}

class ServerTest: OSCServerDelegate {
    lazy var udpServer: OSCServerUDP = {
        let server = OSCServerUDP()
        server.delegate = self
        return server
    }()
    lazy var tcpServer: OSCServerTCP = {
        let server = OSCServerTCP()
        server.delegate = self
        return server
    }()
    
    var useTCP: Bool = false
    var server: OSCServer {
        useTCP ? tcpServer : udpServer
    }
    
    func listenerStateChange(state: NWListener.State) {
        testPrint("Server listener state change: \(state)")
    }
    
    func runTest(expectation: XCTestExpectation, useTCP: Bool = false) {
        self.useTCP = useTCP
        do {
            //set expectation on methods
            testMethods.forEach {
                $0.expectation = expectation
            }
            
            //Register methods on server
            try server.register(methods: testMethods)
            
            //start listening
            try server.listen(serviceName: OSCTestServiceName)
        } catch {
            testPrint("Server startup failed:", error, prefix: String.boom)
            XCTFail(error.localizedDescription)
            expectation.fulfillAll()
        }
    }
}

class MethodTest: OSCMethod {
    var addressPattern: OSCAddressPattern
    var requiredArguments: OSCArgumentTypeTagArray?

    var expectation: XCTestExpectation?

    init(address: OSCAddressPattern, requiredArguments: OSCArgumentTypeTagArray? = nil) {
        self.addressPattern = address
        self.requiredArguments = requiredArguments
    }
    
    func handleMessage(_ message: OSCMessage,
                       for match: OSCPatternMatchType,
                       at timeTag: OSCTimeTag?) {
        testPrint("Handled message: \(message.addressPattern ?? "bad address")",
                  "match: \(match)",
                  "method: \(addressPattern)",
                  "arguments: \(String(describing: message.arguments))",
                  "time tag: \(String(describing: timeTag?.date))")
        expectation?.fulfill()
    }
}

class MulticastTest: OSCMulticastDelegate {
    var expectation: XCTestExpectation? = nil
    lazy var mcast: OSCMulticast = {
        let mcast = OSCMulticast()
        mcast.delegate = self
        return mcast
    }()
    
    func groupStateChange(state: NWConnectionGroup.State) {
        testPrint("state: \(state)")
        
        switch state {
        case .ready:
            send()
            
        case .failed(let error):
            XCTFail(error.localizedDescription)
            
        default:
            break
        }
    }
    
    func runTest(expectation: XCTestExpectation) {
        self.expectation = expectation
        
        do {
            //add expectation to methods and register
            testMethods.forEach {
                $0.expectation = expectation
            }
            try mcast.register(methods: testMethods)
            
            //start listening
            try mcast.joinGroup(on: "224.0.0.251", port: 12345)
            
            testPrint("Multicast Test Started")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func send() {
        do {
            //send messages serially to test queueing
            try testMessages.forEach {
                testPrint("Sending multicast message: \(String(describing: $0.addressPattern))")
                try mcast.send($0) { error in
                    if let error = error {
                        XCTFail(error.localizedDescription)
                    }
                    self.expectation?.fulfill()
                }
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}

//MARK: - Utility

func testPrint(_ items: Any...,
               separator: String = ", ",
               terminator: String = .newline,
               prefix: String = String.test) {
    print(prefix, terminator: .space)
    print(items.map {"\($0)"}.joined(separator: separator),
          terminator: terminator)
}

extension Data {
    static var hexDigits = Array("0123456789ABCDEF".utf16)
    
    ///Hex representation of the bytes in upper case hex characters
    ///
    /// - Note: You can call lowercased() on the result if you prefer lowercase.
    func hexRepresentation() -> String {
        let chars = reduce(into: Array<unichar>(capacity: count * 2)) {
            $0.append(Data.hexDigits[Int($1 / 16)])
            $0.append(Data.hexDigits[Int($1 % 16)])
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}

public extension String {
    //Common
    static var empty: String { "" }
    static var space: String { " " }
    static var comma: String { "," }
    static var newline: String { "\n" }
    
    //Debug
    static var test: String { "????" }
    static var notice: String { "??????" }
    static var warning: String { "????" }
    static var fatal: String { "??????" }
    static var reentry: String { "??????" }
    static var stop: String { "????" }
    static var boom: String { "????" }
    static var sync: String { "????" }
    static var key: String { "????" }
    static var bell: String { "????" }
}

extension XCTestExpectation {
    func fulfillAll() {
        for _ in 1...expectedFulfillmentCount {
            fulfill()
        }
    }
}

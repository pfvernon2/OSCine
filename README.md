# OSCine

OSCine is an easy to use yet robust Swift client and server implementation of Open Sound Control v1.1.

The design goals for this package are:
* Ease of use
* No third-party dependencies
* Close adherance to OSC v1.1 specification
* Integrated TCP, UDP, and Multicast network support*
* Integrated Bonjour advertisement and browsing support
* Integrated OSLog support
* SLIP support via Apple Network Protocol Framer

Future versions will likely support Swift 5.5 async operations.

 * While OSCine has fully integrated network support, access to packet creation and parsing is available so that alternate transport libraries could be utilized if desired. 

> *IMPORTANT*: Multicast support on iOS/iPadOS 14 and later requires [entitlements available only directly from Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_networking_multicast). 

## OSC

OSCine follows the OSC v1.1 specification closely and relies upon terminology from the OSC spec heavily throughout. If you are not familar with OSC and its paradigms it is strongly suggested that you review them before proceeding: 

	http://cnmat.org/OpenSoundControl/OSC-spec.html
	http://opensoundcontrol.org/spec-1_0.html
	http://opensoundcontrol.org/files/2009-NIME-OSC-1.1.pdf

## Usage

Usage is intended to be as straightforward as possible assuming familiarity with OSC and its terminology. The representative examples below, and included test suite, should hopefully get you started. Further information and details can be found as *Swift Documentation Comments* in the code itself.

### Client

```
let client = OSCClientUDP()
client.delegate = self //for connection state notifications - see OSCClientDelegate
client.connect(serviceName: "MyMixer", timeout: 10.0)

//after connection state change to: .ready

let bundle = OSCBundle(timeTag: OSCTimeTag.immediate,
                       bundleElements: [
                           OSCMessage(addressPattern: "/mixer/*/mute[0-9]", arguments: [.true]), 
                           OSCMessage(addressPattern: "/mixer/*/solo[0-9]", arguments: [.false]),
                           OSCMessage(addressPattern: "/mixer/*/fader[0-9]", arguments: [.float(0.0)]), 
                           OSCMessage(addressPattern: "/mixer/*/eq", arguments: [.float(0.0), .float(0.0), .float(0.0)]), 
                           OSCMessage(addressPattern: "/mixer/*/label", arguments: [.string("")]),
                       ])
try client.send(bundle)
```

### Server

```
class MyMethod: OSCMethod {
    var addressPattern: OSCAddressPattern
    var requiredArguments: OSCArgumentTypeTagArray? = nil

    init(addressPattern: OSCAddressPattern, requiredArguments: OSCArgumentTypeTagArray? = nil) {
        self.addressPattern = addressPattern
        self.requiredArguments = requiredArguments
    }
    
    func handleMessage(_ message: OSCMessage, for match: OSCPatternMatchType, at timeTag: OSCTimeTag?) {
        print("Received message: \(message.addressPattern)",
              "with match: \(match)",
              "arguments: \(String(describing: message.arguments)),
              "time tag: \(String(describing: timeTag?.date))"")
    }
}

let server = OSCServerUDP()
server.delegate = self //for listener state notifications - see OSCServerDelegate
try server.register(methods: [MyMethod(addressPattern: "/mixer/main/mute1", requiredArguments: [.anyBoolean]), 
                              MyMethod(addressPattern: "/mixer/main/solo1", requiredArguments: [.anyBoolean]), 
                              MyMethod(addressPattern: "/mixer/main/fader1", requiredArguments: [.float, .optional(.float)]), 
                              MyMethod(addressPattern: "/mixer/main/eq", requiredArguments: [.anyNumber, .anyNumber, .anyNumber]), 
                              MyMethod(addressPattern: "/mixer/main/label"])
try server.listen(serviceName: "MyMixer")
```

### Multicast

```
let mcast = OSCMulticast()
mcast.delegate = self //for group state notifications - see OSCMulticastDelegate
try mcast.joinGroup(on: "224.0.0.251", port: 12345)

//Register methods if you care to process or monitor messages sent to the group
try mcast.register(methods: [MyMethod(addressPattern: "/mixer/main/mute1", requiredArguments: [.anyBoolean]), 
                             MyMethod(addressPattern: "/mixer/main/solo1", requiredArguments: [.anyBoolean]), 
                             MyMethod(addressPattern: "/mixer/main/fader1", requiredArguments: [.float, .optional(.float)]), 
                             MyMethod(addressPattern: "/mixer/main/eq", requiredArguments: [.anyNumber, .anyNumber, .anyNumber]), 
                             MyMethod(addressPattern: "/mixer/main/label")

//Note that Messages sent to the group will also be delivered to any Methods you register on the Multicast instance.
let bundle = OSCBundle(timeTag: OSCTimeTag.immediate,
                       bundleElements: [
                            OSCMessage(addressPattern: "/mixer/*/mute[0-9]", arguments: [.true]), 
                            OSCMessage(addressPattern: "/mixer/*/solo[0-9]", arguments: [.false]),
                            OSCMessage(addressPattern: "/mixer/*/fader[0-9]", arguments: [.float(0.0)]), 
                            OSCMessage(addressPattern: "/mixer/*/eq", arguments: [.float(0.0), .float(0.0), .float(0.0)]), 
                            OSCMessage(addressPattern: "/mixer/*/label", arguments: [.string("")]),
                       ])
try mcast.send(bundle)
```


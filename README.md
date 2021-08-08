# OSCine

OSCine is a simple robust Swift client and server implementation of Open Sound Control v1.1.

The design goals for this package are:
* Ease of use
* No third party dependencies
* Close adherance to OSC v1.1 specification
* Integrated TCP, UDP, and Multicast network support*
* Integrated Bonjour advertisement and browsing support
* Integrated OSLog support
* SLIP support via Apple Network Protocol Framer

Future versions will likely support Swift 5.5 async operations.

 * While OSCine has fully integrated network support, access to packet creation and parsing is available so that alternate transport libraries could be utilized if desired. 

## OSC

OSCine follows the OSC v1.1 specification closely and relies upon terminology from the OSC spec heavily throughout. If you are not familar with OSC and its paradigms it is strongly suggested that you review them before proceeding: 

#### Overview:
	http://cnmat.org/OpenSoundControl/OSC-spec.html
    
#### The nitty gritty:
	http://opensoundcontrol.org/spec-1_0.html
	http://opensoundcontrol.org/files/2009-NIME-OSC-1.1.pdf

## Usage

### Client

* OSCClientUDP/OSCClientTCP & OSCClientDelegate
* OSCMessage & OSCBundle
* OSCAddressPattern & OSCArgument

If you are developing an OSC client you will need to insantiate one of the `OSCClientUDP` or `OSCClientTCP` classes. Additionally you will need to implement a class conforming to `OSCClientDelegate` in order to monitor the network state change information.

To begin sending messages from your client call  `client.connect()` with either a specific address and port or the name of the Bonjour service to browse for. By default the standard OSC service types `_osc._udp` and `_osc._tcp` are used for browsing but this can be set to any custom service type you may care to use. 

> *Note -* For consistency with the Apple Network Framework I have carried through the concept of `connect()` but be aware that UDP is a "connectionless" protocol and this terminology is potentially misleading. When using a UDP client the `connect()` method prepares the network stack to send datagrams to the specified address/port but does not imply, or ensure, that a server is listening at that given address/port. 

In order to send OSC messages via your client instantiate one or both of the `OSCMessage` and `OSCBundle` classes. The `OSCMessage` class has two required properties: `addressPattern` and `arguments`. 

The `addressPattern` is either a literal representation of the path to which you want to send a message to a `method` or `container` on the server, or it may be a descriptive "wildcard" represenation of the path, i.e. `/path/to/control` or `/path/*/control`. There are a number of wildcard options which may be combined in a variety of ways. Please refer to OSC specfication for details on wildcard usage and limitations.

The `arguments` are an ordered array of enumeration values as defined by `OSCArgument`.

The following is a minimaly functional UDP based OSC client with Bonjour service discovery:
```
let client = OSCClientUDP()
client.delegate = self //for connection state notifications
client.connect(serviceName: "MyMixer", timeout: 10.0)

//after connection state change to: .ready

let bundle = OSCBundle(timeTag: OSCTimeTag.immediate,
                       bundleElements: [
                           OSCMessage(addressPattern: "/mixer/*/mute[0-9]", arguments: [.boolean(true)]), 
                           OSCMessage(addressPattern: "/mixer/*/solo[0-9]", arguments: [.boolean(true)]),
                           OSCMessage(addressPattern: "/mixer/*/fader[0-9]", arguments: [.float(0.0)]), 
                           OSCMessage(addressPattern: "/mixer/*/eq", arguments: [.float(0.0), .float(0.0), .float(0.0)]), 
                           OSCMessage(addressPattern: "/mixer/*/label", arguments: [.string("")]),
                       ])
try client.send(bundle)
```

### Server

* OSCServerUDP/OSCServerTCP & OSCServerDelegate
* OSCMethod & OSCMessage
* OSCAddressPattern & OSCArgument

If you are developing an OSC server you will need to insantiate one of the `OSCServerUDP` or `OSCServerTCP` classes. Additionally you will need to implement a class conforming to `OSCServerDelegate` in order to monitor the network state change information.

To begin receiving messages call `server.listen()` with a specific port and/or the name to advertise as your Bonjour service. 

> *Note -* If you are relying upon Bonjour for client browsing it is advised you *not* to specify a port. If you do not specify a port the network stack will assign a port randomly and Bonjour will advertise said port for you. 

In order to process OSC messages you will need to register one or more classes conforming to the protocol `OSCMethod` on your server instance. To implement a method you will need to provide, at a minimium, an `addressPattern` var and a `handleMessage()` function. Your `handleMessage()` function will be called when either an exact or wildcard match for the specified `OSCAddressPattern` is received. 

Optionally you can supply a pattern of argument types to `requiredArguments` which can be used to validate that messages have the required arguments prior to being delivered to your `handleMessage` function.

The following is a minimaly functional UDP based OSC server with Bonjour service advertisement:
```
class MyMethod: OSCMethod {
    var addressPattern: OSCAddressPattern
    var requiredArguments: OSCArgumentTypeTagArray? = nil

    init(addressPattern: OSCAddressPattern, requiredArguments: OSCArgumentTypeTagArray? = nil) {
        self.addressPattern = addressPattern
    }
    
    func handleMessage(_ message: OSCMessage, for match: OSCPatternMatchType) {
        print("Received message: \(message.addressPattern)",
              "match: \(match)",
              "arguments: \(String(describing: message.arguments))")
    }
}

let mixerMainMute = MyMethod(addressPattern: "/mixer/main/mute1", requiredArguments: [.anyBoolean])
let mixerMainSolo = MyMethod(addressPattern: "/mixer/main/solo1", requiredArguments: [.anyBoolean])
let mixerMainFader = MyMethod(addressPattern: "/mixer/main/fader1", requiredArguments: [.float, .optional(.float)])
let mixerMainEQ = MyMethod(addressPattern: "/mixer/main/eq", requiredArguments: [.anyNumber, .anyNumber, .anyNumber])
let mixerMainLabel = MyMethod(addressPattern: "/mixer/main/label", requiredArguments: [.anyTag])

let server = OSCServerUDP()
server.delegate = self //for listener state notifications
try server.register(methods: [mixerMainMute, 
                              mixerMainSolo, 
                              mixerMainFader, 
                              mixerMainEQ, 
                              mixerMainLabel])
try server.listen(serviceName: "MyMixer")
```

### Multicast

* OSCMulticastClientServer & OSCMulticastClientServerDelegate
* OSCMethod & OSCMessage & OSCBundle
* OSCAddressPattern & OSCArgument

While not detailed in the OSC specification a number of implementations allow for multicast send and receive of OSC messages and bundles. This is implemented in OSCine as a combination client and server class `OSCMulticastClientServer` which allows for simultaneous send and receive of OSC messages and bundles via a single multicast address and port. This combination design also allows for easy synchronization of OSC methods both within your app and with other devices on the network.

> *IMPORTANT*: Multicast support on iOS/iPadOS 14 and later requires [entitlements available only directly from Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_networking_multicast). 

The following is a minimaly functional Multicast implementation:
```
let mcast = OSCMulticastClientServer()
mcast.delegate = self //for group state notifications

//Begin receiving and dispatching messages to methods
let mixerMainMute = MyMethod(addressPattern: "/mixer/main/mute1", requiredArguments: [.anyBoolean])
let mixerMainSolo = MyMethod(addressPattern: "/mixer/main/solo1", requiredArguments: [.anyBoolean])
let mixerMainFader = MyMethod(addressPattern: "/mixer/main/fader1", requiredArguments: [.float, .optional(.float)])
let mixerMainEQ = MyMethod(addressPattern: "/mixer/main/eq", requiredArguments: [.anyNumber, .anyNumber, .anyNumber])
let mixerMainLabel = MyMethod(addressPattern: "/mixer/main/label", requiredArguments: [.anyTag])
try mcast.register(methods: [mixerMainMute, 
                             mixerMainSolo, 
                             mixerMainFader, 
                             mixerMainEQ,
                             mixerMainLabel])
try mcast.listen(on: "224.0.0.251", port: 12345)

//Send bundle to all in the multicast group, including ourselves
let bundle = OSCBundle(timeTag: OSCTimeTag(immediate: true),
                       bundleElements: [
                            OSCMessage(addressPattern: "/mixer/*/mute[0-9]", arguments: [.true]), 
                            OSCMessage(addressPattern: "/mixer/*/solo[0-9]", arguments: [.false]),
                            OSCMessage(addressPattern: "/mixer/*/fader[0-9]", arguments: [.float(0.0)]), 
                            OSCMessage(addressPattern: "/mixer/*/eq", arguments: [.float(0.0), .float(0.0), .float(0.0)]), 
                            OSCMessage(addressPattern: "/mixer/*/label", arguments: [.string("")]),
                       ])
try mcast.send(bundle)
```

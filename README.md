# OSCine

OSCine is a simple robust Swift client and server implementation of Open Sound Control v1.1.

The design goals for this package are:
* Ease of use
* Minimal public interface
* No third party dependencies
* Close adherance to OSC v1.1 protcol
* Support for TCP, UDP, and Multicast
* Integrated Bonjour advertisement and browsing
* Integrated OSLog support
* SLIP support via Apple Network Protocol Framer

Future versions will likely support Swift 5.5 async operations.

### Why another OSC library in Swift? 

I created this package for my own uses as I found the available open source packages lacking, primarily in their requirements for thirdparty dependencies. Initially I was not planning to release this, however in the process of developing it I found Apples documentation and examples for creating Network Protocol Framers to be shamefully lacking. I felt it was worth contributing this example back to the community simply to make another protocol framer example available. 

## OSC

OSCine follows the OSC specification closely and relies upon terminology from the OSC spec heavily throughout. If you are not familar with OSC and its paradigms it is strongly suggested that you review them before proceeding: 

#### Overview:
	http://cnmat.org/OpenSoundControl/OSC-spec.html
    
#### The nitty gritty:
	http://opensoundcontrol.org/spec-1_0.html
	http://opensoundcontrol.org/files/2009-NIME-OSC-1.1.pdf

## Usage

As a user of this package you should expect to interact with the various classes differently based upon your use case: Client, Server, or Multicast.

### Client usage

* OSCClientUDP/OSCClientTCP & OSCClientDelegate
* OSCMessage & OSCBundle
* OSCArgument Implementations

If you are building an OSC client you will need to insantiate one of the `OSCClientUDP` or `OSCClientTCP` classes. Additionally you will need to implement a class conforming to `OSCClientDelegate` in order to monitor the network state change information.

To begin sending messages from your client call  `client.connect()` with either a specific address and port or the name of the Bonjour service to browse for. By default the standard OSC service types `_osc._udp` and `_osc._tcp` are used for browsing but this can be set to any custom service type you may care to use. 

>> *Note -* For consistency with the Apple Network Framework I have carried through the concept of `connect()` but be aware that UDP is a "connectionless" protocol and this terminology is potentially misleading. When using a UDP client the `connect()` method prepares the network stack to send datagrams to the specified address/port but does not imply, or ensure, that a server is listening at that given address/port. 

In order to send OSC messages via your client instantiate one or both of the `OSCMessage` and `OSCBundle` classes. The `OSCMessage` class has two properties: `addressPattern` and `arguments`. 

The `addressPattern` is either a literal representation of the path to which you want to send a message to a `method` or `container` on the server, or it may be a descriptive "wildcard" represenation of the path. For example `/path/to/control` or `/path/*/control`. There are a number of wildcard options which may be combined in a variety of ways. Please refer to OSC specfication for details on wildcard usage and limitations.

The  `arguments` are an ordered array of objects conforming to the `OSCArgument` protocol. OSC supports a specific set of argument types. These are represted in OSCine as: `OSCInt, OSCFloat, OSCBool, OSCString, OSCBlob, OSCNull, OSCImpulse, and OSCTimeTag`

The following is a minimaly functional UDP based OSC client with Bonjour service discovery:
```
let client = OSCClientUDP()
client.delegate = self //for connection state notifications
client.connect(serviceName: "MyMixer", timeout: 10.0)

//after connection state change to: .ready

let bundle = OSCBundle(timeTag: OSCTimeTag.immediate,
                       bundleElements: [
                           OSCMessage(address: "/mixer/*/mute*", arguments: [OSCBool(true)]), 
                           OSCMessage(address: "/mixer/*/solo*", arguments: [OSCBool(false)]),
                           OSCMessage(address: "/mixer/*/fader*", arguments: [OSCFloat(0.0)]), 
                           OSCMessage(address: "/mixer/*/label*", arguments: [OSCString("")]),
                       ])
client.send(bundle)
```

### Server usage

* OSCServerUDP/OSCServerTCP & OSCServerDelegate
* OSCMethod & OSCMessage
* OSCArgument Implementations

If you are building an OSC server you will need to insantiate one of the `OSCServerUDP` or `OSCServerTCP` classes. Additionally you will need to implement a class conforming to `OSCServerDelegate` in order to monitor the network state change information.

To begin receiving messages call `server.listen()` with a specific port and/or the name to advertise as your Bonjour service. 

>> *Note -* If you are relying upon Bonjour for client browsing it is advised *not* to specify a port. If you do not specify a port the network stack will assign a port randomly and Bonjour will advertise said port for you. 

In order to process OSC messages you will need to register one or more `OSCMethod` classes on your server instance. To implement a method you will need to provide an `addressPattern` var and a `handleMessage()` function. Your `handleMessage()` function will be called when either an exact or wildcard match for the specified `OSCAddressPattern` is received. 

The following is a minimaly functional UDP based OSC server with Bonjour service advertisement:
```
class MyMethod: OSCMethod {
    var addressPattern: OSCAddressPattern
    
    init(address: OSCAddressPattern) {
        self.addressPattern = address
    }
    
    func handleMessage(_ message: OSCMessage, for match: OSCPatternMatchType) {
        print("Received message: \(message.addressPattern)",
              "match: \(match)",
              "arguments: \(String(describing: message.arguments))")
    }
}

let mixerMainMute = MyMethod(address: "/mixer/main/mute1")
let mixerMainSolo = MyMethod(address: "/mixer/main/solo1")
let mixerMainFader = MyMethod(address: "/mixer/main/fader1")
let mixerMainLabel = MyMethod(address: "/mixer/main/label1")

let server = OSCServerUDP()
server.delegate = self //for listener state notifications
server.register(methods: [mixerMainMute, 
                          mixerMainSolo, 
                          mixerMainFader, 
                          mixerMainLabel])
server.listen(serviceName: "MyMixer")
```

### Multicast

* OSCMulticastClientServer & OSCMulticastClientServerDelegate
* OSCMethod & OSCMessage & OSCBundle
* OSCArgument Implementations

While not detailed in the OSC specification a number of implementations allow for multicast send and receive of OSC messages and bundles. This is implemented in OSCine as a combination client and server class `OSCMulticastClientServer` which allows for simultaneous send and receive of OSC messages and bundles via a single multicast address and port. This combination design also allows for easy synchronization of OSC methods both within your app and with other devices on the network.

>> *IMPORTANT*: Multicast support on iOS and iPadOS 14 and later [requires entitlements available only directly from Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_networking_multicast). 

The following is a minimaly functional Multicast implementation:
```
let mcast = OSCMulticastClientServer()
mcast.delegate = self //for group state notifications

//Begin receiving and dispatching messages to methods
let mixerMainMute = MyMethod(address: "/mixer/main/mute1"")
let mixerMainSolo = MyMethod(address: "/mixer/main/solo1"")
let mixerMainFader = MyMethod(address: "/mixer/main/fader1")
let mixerMainLabel = MyMethod(address: "/mixer/main/label1")
mcast.register(methods: [mixerMainMute, 
                          mixerMainSolo, 
                          mixerMainFader, 
                          mixerMainLabel])
try mcast.listen(on: "224.0.0.251", port: 12345)

//Send bundle to all in the multicast group, including ourselves
let bundle = OSCBundle(timeTag: OSCTimeTag(immediate: true),
                       bundleElements: [
                           OSCMessage(address: "/mixer/*/mute*", arguments: [OSCBool(true)]), 
                           OSCMessage(address: "/mixer/*/solo*", arguments: [OSCBool(false)]),
                           OSCMessage(address: "/mixer/*/fader*", arguments: [OSCFloat(0.0)]), 
                           OSCMessage(address: "/mixer/*/label*", arguments: [OSCString("")]),
                       ])
mcast.send(bundle)
```

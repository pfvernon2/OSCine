# OSCine

OSCine is a simple robust Swift implementation of Open Sound Control v1.1 which supports UDP and TCP and includes automatic Bonjour advertising and browsing. Both Server and Client implementations are included.

This package has no external dependencies. It is written for Swift 5.4. All networking and discovery is managed by the Apple Network Framework.

Future versions will likely support Swift 5.5 async operations.

## OSC

OSCine follows the OSC specification closely and uses terminology from the OSC spec heavily throughout. If you are not familar with OSC and its paradigms it is strongly suggested that you review them before proceeding: 

#### Overview:
    http://cnmat.org/OpenSoundControl/OSC-spec.html
    
#### The nitty gritty:
    http://opensoundcontrol.org/spec-1_0.html
    http://opensoundcontrol.org/files/2009-NIME-OSC-1.1.pdf

## Usage

As a user of this package you should expect to interact with the various classes differently based upon your use case: Client or Server.

### Client usage

* OSCClientUDP/OSCClientTCP & OSCClientDelegate
* OSCMessage & OSCBundle
* OSCDataType Implementations

If you are building an OSC client. You should expect to interact primarly with with one or both of the `OSCClientUDP` and `OSCClientTCP` classes. Additionally both of these classes depend upon the `OSCClientDelegate` class for reporting network connection state change information back to the class managing the client.

To begin sending messages from your client one would typically call  `client.connect()` with either a specific address and port or the name of the Bonjour service to connect to a running OSC Server.

*IMPORTANT*: I have carried through the concept of `connect()` from the Apple Network Framework but be aware that UDP is a "connectionless" protocol and this terminology is potentially misleading. When using a UDP client the `connect()` method simply prepares the network stack to send messages. UDP messages are sent without any expectation or confirmation of delivery and the OSC protocol also provides no such functionality. If you require assurance of delivery (at the potential expense of slower, or even delayed, delivery) you should use the TCP protocol. If you require timely delivery, and can handle the potential loss of messages, UDP is generally more efficient.  

In order to send OSC messages via your client use the `OSCMessage` and/or `OSCBundle` classes. A message is fundamental unit of information exchange in OSC and bundles are collections of messages (and other bundles.) 

The `OSCMessage` class has two properties: The `address pattern`, and the `arguments`. 

The `address pattern` is either a literal representation of the path to which you want to send a message to a `method` or `container` on the server, or it may be a descriptive "wildcard" represenation of the path.  For example `/path/to/control` or `/path/*/control`. There are a number of wildcard options which may be combined in a variety of ways.

The  `arguments` are an ordered array of objects conforming to the `OSCDataType` protocol. OSC supports a specific set of data types. These are represted in OSCine as: `OSCInt, OSCFloat, OSCBool, OSCString, OSCBlob, OSCNull, OSCImpulse, and OSCTimeTag`

The following is all that is required for a minimaly functional UDP based OSC client with Bonjour discovery:
```
let bundle = OSCBundle(timeTag: OSCTimeTag(immediate: true),
                       bundleElements: [
                           OSCMessage(address: "/mixer/*/mute*", arguments: [OSCBool(true)]), 
                           OSCMessage(address: "/mixer/*/solo*", arguments: [OSCBool(false)]),
                           OSCMessage(address: "/mixer/*/fader*", arguments: [OSCFloat(0.0)]), 
                           OSCMessage(address: "/mixer/*/label*", arguments: [OSCString("")]),
                       ])

let client = OSCClientUDP()
client.delegate = self //for connection state notifications
client.connect(serviceName: "MyMixer", timeout: 10.0)
//after connection state change: .ready
client.send(bundle)
```

### Server usage

* OSCServerUDP/OSCServerTCP & OSCServerDelegate
* OSCMethod
* OSCMessage
* OSCDataType Implementations

If you are building an OSC server. You should expect to interact primarly with with one or both of the `OSCServerUDP` and `OSCServerTCP` classes. Additionally both of these classes depend upon the `OSCServerDelegate` class for reporting network connection state change information back to the class managing the server.

To begin receiving messages one would typically call  `server.listen()` with a specific port and/or the name for your Bonjour service. Note that if you are using Bonjour for your client connection discovery it is advised *not* to specify a specific port. If you do not specify a port the network stack will assign a port randomly and Bonjour will advertise said port for you. In general it is best to not specify specific ports if possible as it adds complexity to your server setup and error handling. 

In order to receive OSC messages you will need to register one or more `OSCMethod` classes on your server instance. To implement a method you will need to provide an `OSCAddressPattern` var and a `handleMessage()` function. Your `handleMessage()` function will be called when a match for the specified `OSCAddressPattern` is received. Unlike client messages which may specify wildcards your `OSCAddressPattern` must be a valid and fully qualified OSC Address Pattern. 

The following is all that is required for a minimaly functional UDP based OSC server with Bonjour discovery:
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

let mixerMainMute = MyMethod(address: "/mixer/main/mute1"")
let mixerMainSolo = MyMethod(address: "/mixer/main/solo1"")
let mixerMainFader = MyMethod(address: "/mixer/main/fader1")
let mixerMainLabel = MyMethod(address: "/mixer/main/label1")

let server = OSCServerUDP()
server.register(methods: [mixerMainMute, 
                          mixerMainSolo, 
                          mixerMainFader, 
                          mixerMainLabel])
server.listen(serviceName: "MyMixer")
```

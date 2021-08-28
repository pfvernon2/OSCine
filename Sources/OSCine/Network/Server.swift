//
//  Server.swift
//  
//
//  Created by Frank Vernon on 6/30/21.
//

import Foundation
import Network

//MARK: - OSCServerDelegate

///Delegate for notifications of network state change
public protocol OSCServerDelegate: AnyObject {
    func listenerStateChange(state: NWListener.State)
}

//MARK: - OSCServer

///Protocol defining OSC server behavior
public protocol OSCServer: AnyObject {
    var delegate: OSCServerDelegate? { get set }
    var serviceType: String { get set }

    func listen(on port: NWEndpoint.Port, serviceName: String?) throws
    func cancel()
    func shutdown()
    
    func register(method: OSCMethod) throws
    func register(methods: [OSCMethod]) throws
    
    func deregister(method: OSCMethod)
    func deregisterAll()
}

//MARK: - OSCServerUDP

///UDP based OSC server
public class OSCServerUDP: OSCServer, NetworkServer {
    weak public var delegate: OSCServerDelegate? = nil
    public var serviceType: String = kOSCServiceTypeUDP
    
    internal var listener: NWListener? = nil
    internal var parameters: NWParameters = {
        var params: NWParameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        params.includePeerToPeer = true
        return params
    }()
    internal var manager: OSCConnectionManager = OSCConnectionManager()
    
    public init() {}
    deinit {
        shutdown()
    }
}

//MARK: - OSCServerTCP

///TCP based OSC server
public class OSCServerTCP: OSCServer, NetworkServer {
    weak public var delegate: OSCServerDelegate? = nil
    public var serviceType: String = kOSCServiceTypeTCP
    
    internal var listener: NWListener? = nil
    internal var parameters: NWParameters = {
        //Customize TCP options to enable keepalives
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        
        //Enable peer to peer and endpoint reuse by default
        var params: NWParameters = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true
        
        //Insert our SLIP protocol framer at the top of the stack
        let SLIPOptions = NWProtocolFramer.Options(definition: SLIPProtocol.definition)
        params.defaultProtocolStack.applicationProtocols.insert(SLIPOptions, at: .zero)
        return params
    }()
    internal var manager: OSCConnectionManager = OSCConnectionManager()
    
    public init() {}
    deinit {
        shutdown()
    }
}

//MARK: - OSCNetworkServer protocol

internal protocol NetworkServer: AnyObject {
    var listener: NWListener? { get set }
    var parameters: NWParameters { get set }
    var manager: OSCConnectionManager { get set }
}

public extension OSCServer {
    func listen(on port: NWEndpoint.Port = .any, serviceName: String? = nil) throws {
        guard let server = self as? NetworkServer else {
            fatalError("Adoption of OSCServer requires additional adoptance of NetworkServer")
        }
        
        server.listener = try NWListener(using: server.parameters, on: port)
        
        //advertise service if given a name
        if let serviceName = serviceName {
            server.listener?.service = NWListener.Service(name: serviceName, type: serviceType)
        }
        
        server.listener?.stateUpdateHandler = { [weak self, weak server] (state) in
            switch state {
            case .failed(let error):
                OSCLogDebug("Listener failed: \(error.debugDescription)")
                fallthrough
            case .cancelled:
                server?.manager.cancelAll()
                server?.listener = nil
                
            default:
                break
            }
            
            self?.delegate?.listenerStateChange(state: state)
        }
        
        server.listener?.newConnectionHandler = { [weak server] (connection) in
            OSCLogDebug("Received connection from: \(connection.debugDescription)")
            server?.manager.add(connection: connection)
        }
        
        OSCLogDebug("Starting listener: \(server.listener?.debugDescription ?? "?")")
        server.listener?.start(queue: .main)
    }
    
    ///Stops the listener but leaves active client connections running
    func cancel() {
        guard let server = self as? NetworkServer else {
            fatalError("Adoption of OSCServer requires additional adoptance of NetworkServer")
        }
        
        server.listener?.cancel()
    }
    
    func register(methods: [OSCMethod]) throws {
        guard let server = self as? NetworkServer else {
            fatalError("Adoption of OSCServer requires additional adoptance of NetworkServer")
        }
        
        try server.manager.addressSpace.register(methods: methods)
    }
    
    func register(method: OSCMethod) throws {
        try register(methods: [method])
    }
    
    func deregister(method: OSCMethod) {
        guard let server = self as? NetworkServer else {
            fatalError("Adoption of OSCServer requires additional adoptance of NetworkServer")
        }
        
        server.manager.addressSpace.deregister(method: method)
    }
    
    func deregisterAll() {
        guard let server = self as? NetworkServer else {
            fatalError("Adoption of OSCServer requires additional adoptance of NetworkServer")
        }
        
        server.manager.addressSpace.removeAll()
    }
    
    ///Stops the listener and disconnects any active client connections
    func shutdown() {
        guard let server = self as? NetworkServer else {
            fatalError("Adoption of OSCServer requires additional adoptance of NetworkServer")
        }

        cancel()
        server.manager.cancelAll()
    }
}

//MARK: - OSCConnectionManager

///Internal class to manage server connections for Apple Network Framework
internal class OSCConnectionManager {
    var addressSpace = OSCAddressSpace()
    var connections = Array<NWConnection>()
    
    func add(connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] (state) in
            switch state {
            case .ready:
                self?.receiveNextMessage(connection: connection)
                
            case .failed(let error):
                OSCLogDebug("\(connection.debugDescription) failed: \(error.debugDescription)")
                fallthrough
            case .cancelled:
                self?.remove(connection: connection)
                
            default:
                break
            }
        }
        
        OSCLogDebug("Starting connection from: \(connection.debugDescription)")
        connection.start(queue: .main)
    }
    
    func remove(connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }
    
    func receiveNextMessage(connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard error == nil else {
                //force unwrap protected by guard
                OSCLogError("receiveMessage failure: \(error!.localizedDescription)")
                return
            }
            
            if isComplete, let content = content {
                do {
                    let element = try content.parseOSCPacket()
                    self?.addressSpace.dispatch(element: element)
                } catch {
                    OSCLogError("OSCPacket decode failure: \(error.localizedDescription)")
                }
            }
            
            self?.receiveNextMessage(connection: connection)
        }
    }
    
    func cancelAll() {
        connections.forEach { $0.cancel() }
    }
}

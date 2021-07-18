//
//  Server.swift
//  
//
//  Created by Frank Vernon on 6/30/21.
//

import Foundation
import Network

//MARK: - Definitions

public let kOSCServiceTypeUDP: String = "_osc._udp"
public let kOSCServiceTypeTCP: String = "_osc._tcp"

enum OSCNetworkingError: Error {
    case invalidNetworkDesignation
    case notConnected
}

//MARK: - OSCServerDelegate

protocol OSCServerDelegate: AnyObject {
    func listenerStateChange(state: NWListener.State)
}

//MARK: - OSCNetworkServer protocol

protocol OSCNetworkServer: AnyObject {
    var serviceType: String { get set }
    var delegate: OSCServerDelegate? { get set }
    var listener: NWListener? { get set }
    var parameters: NWParameters { get set }
    var manager: OSCServerConnectionManager { get }
    
    func listen(on port: NWEndpoint.Port, serviceName: String?) throws
    func cancel()
    
    func register(method: OSCMethod) throws
    func deregister(method: OSCMethod)
    
    func deregisterAll()
}

extension OSCNetworkServer {
    func listen(on port: NWEndpoint.Port = .any, serviceName: String? = nil) throws {
        listener = try NWListener(using: parameters, on: port)
        
        //advertise service if given a name
        if let serviceName = serviceName {
            listener?.service = NWListener.Service(name: serviceName, type: serviceType)
        }

        listener?.stateUpdateHandler = { [weak self] (state) in
            if state == .cancelled {
                self?.manager.cancelAll()
                self?.listener = nil
            }
            
            self?.delegate?.listenerStateChange(state: state)
        }
        
        listener?.newConnectionHandler = { [weak self] (connection) in
            self?.manager.add(connection: connection)
        }
        
        listener?.start(queue: .main)
    }
    
    func cancel() {
        listener?.cancel()
    }
        
    func register(methods: [OSCMethod]) throws {
        try methods.forEach {
            try register(method: $0)
        }
    }
    
    func register(method: OSCMethod) throws {
        guard method.addressPattern.isValidOSCAddress() else {
            throw OSCEncodingError.invalidAddress
        }

        manager.addressSpace.register(method: method)
    }

    func deregister(method: OSCMethod) {
        manager.addressSpace.deregister(method: method)
    }
    
    func deregisterAll() {
        manager.addressSpace.removeAll()
    }
}

//MARK: - OSCServerUDP

class OSCServerUDP: OSCNetworkServer {
    var serviceType: String = kOSCServiceTypeUDP
    weak var delegate: OSCServerDelegate? = nil
    internal var listener: NWListener? = nil
    internal var parameters: NWParameters = {
        var params: NWParameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        params.includePeerToPeer = true
        return params
    }()
    internal var manager = OSCServerConnectionManager()
    
    deinit {
        listener?.cancel()
    }
}

//MARK: - OSCServerTCP

class OSCServerTCP: OSCNetworkServer {
    var serviceType: String = kOSCServiceTypeTCP
    weak var delegate: OSCServerDelegate? = nil
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
    internal var manager = OSCServerConnectionManager()
    
    deinit {
        listener?.cancel()
    }
}

//MARK: - OSCConnectionManager
internal typealias NWConnectionArray = Array<NWConnection>
internal class OSCServerConnectionManager {
    var addressSpace = OSCAddressSpace()
    var connections = NWConnectionArray()
    
    func add(connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] (newState) in
            switch newState {
            case .ready:
                self?.receiveNextMessage(connection: connection)
            case .cancelled, .failed(_):
                self?.remove(connection: connection)
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    func remove(connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }

    func receiveNextMessage(connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard error == nil else {
                return
            }
            
            if isComplete, let content = content {
                do {
                    let packet = try OSCPacketFactory.decodeOSCPacket(packet: content)
                    self?.addressSpace.dispatch(packet: packet)
                } catch {
                    //TODO: Error handling, report to server delegate? 
                }
            }
            
            self?.receiveNextMessage(connection: connection)
        }
    }
    
    func cancelAll() {
        connections.forEach { $0.cancel() }
    }
}


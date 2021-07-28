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

public enum OSCNetworkingError: Error {
    case invalidNetworkDesignation
    case notConnected
}

//MARK: - OSCNetworkServerDelegate

public protocol OSCNetworkServerDelegate: AnyObject {
    func listenerStateChange(state: NWListener.State)
}

//MARK: - OSCNetworkServer protocol

protocol OSCNetworkServer: AnyObject {
    var serviceType: String { get set }
    var delegate: OSCNetworkServerDelegate? { get set }
    var listener: NWListener? { get set }
    var parameters: NWParameters { get set }
    var manager: OSCConnectionManager { get set }
    
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
            switch state {
            case .failed(let error):
                OSCNetworkLogger.debug("Listener failed: \(error.debugDescription)")
                fallthrough
            case .cancelled:
                self?.manager.cancelAll()
                self?.listener = nil
                
            default:
                break
            }
            
            self?.delegate?.listenerStateChange(state: state)
        }
        
        listener?.newConnectionHandler = { [weak self] (connection) in
            OSCNetworkLogger.debug("Received connection from: \(connection.debugDescription)")
            self?.manager.add(connection: connection)
        }
        
        OSCNetworkLogger.debug("Starting listener: \(self.listener?.debugDescription ?? "?")")
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

public class OSCServerUDP: OSCNetworkServer {
    weak var delegate: OSCNetworkServerDelegate? = nil

    internal var serviceType: String = kOSCServiceTypeUDP
    internal var listener: NWListener? = nil
    internal var parameters: NWParameters = {
        var params: NWParameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        params.includePeerToPeer = true
        return params
    }()
    internal var manager: OSCConnectionManager = OSCConnectionManager()

    deinit {
        cancel()
    }
}

//MARK: - OSCServerTCP

public class OSCServerTCP: OSCNetworkServer {
    weak var delegate: OSCNetworkServerDelegate? = nil

    internal var serviceType: String = kOSCServiceTypeTCP
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
    
    deinit {
        cancel()
    }
}

//MARK: - OSCConnectionManager

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
                OSCNetworkLogger.debug("\(connection.debugDescription) failed: \(error.debugDescription)")
                fallthrough
            case .cancelled:
                self?.remove(connection: connection)
                
            default:
                break
            }
        }
        
        OSCNetworkLogger.debug("Starting connection from: \(connection.debugDescription)")
        connection.start(queue: .main)
    }
    
    func remove(connection: NWConnection) {
        connections.removeAll { $0 === connection }
    }

    func receiveNextMessage(connection: NWConnection) {
        connection.receiveMessage { [weak self] (content, context, isComplete, error) in
            guard error == nil else {
                OSCNetworkLogger.error("receiveMessage failure: \(error!.localizedDescription)")
                return
            }

            if isComplete, let content = content {
                do {
                    let packet = try OSCPacketFactory.decodeOSCPacket(packet: content)
                    self?.addressSpace.dispatch(packet: packet)
                } catch {
                    OSCNetworkLogger.error("OSCPacket decode failure: \(error.localizedDescription)")
                }
            }
            
            self?.receiveNextMessage(connection: connection)
        }
    }
    
    func cancelAll() {
        connections.forEach { $0.cancel() }
    }
}

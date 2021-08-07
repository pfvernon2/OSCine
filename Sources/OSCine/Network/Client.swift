//
//  Client.swift
//  
//
//  Created by Frank Vernon on 6/30/21.
//

import Foundation
import Network

//MARK: - OSCClientDelegate

///Delegate for notifications of network state change of the client
public protocol OSCClientDelegate: AnyObject {
    func connectionStateChange(_ state: NWConnection.State)
}

//MARK: - OSCClient

public protocol OSCClient: AnyObject {
    var delegate: OSCClientDelegate? { get set }
    var serviceType: String { get set }
    
    func connect(host: NWEndpoint.Host, port: NWEndpoint.Port)
    func connect(serviceName: String, timeout: TimeInterval?)
    func connect(endpoint: NWEndpoint)
    
    func disconnect()
    
    func send(_ message: OSCMessage, completion: @escaping (NWError?)->Swift.Void) throws
    func send(_ bundle: OSCBundle, completion: @escaping (NWError?)->Swift.Void) throws
}

//MARK: - OSCClientUDP

///UDP based OSC client
public class OSCClientUDP: OSCClient, NetworkClient {
    weak public var delegate: OSCClientDelegate? = nil
    public var serviceType: String = kOSCServiceTypeUDP
    
    internal var connection: NWConnection? = nil
    internal var parameters: NWParameters = {
        var params: NWParameters = .udp
        params.includePeerToPeer = true
        return params
    }()
    internal var browser: OSCServiceBrowser? = nil
    
    public init() {}
    deinit {
        connection?.cancel()
    }
}

//MARK: - OSCClientTCP

///TCP based OSC client
public class OSCClientTCP: OSCClient, NetworkClient {
    weak public var delegate: OSCClientDelegate? = nil
    public var serviceType: String = kOSCServiceTypeTCP
    
    internal var connection: NWConnection? = nil
    internal var parameters: NWParameters = {
        // Customize TCP options to enable keepalives.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        tcpOptions.noDelay = true
        
        var params: NWParameters = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true
        
        //Insert our SLIP protocol framer at the top of the stack
        let SLIPOptions = NWProtocolFramer.Options(definition: SLIPProtocol.definition)
        params.defaultProtocolStack.applicationProtocols.insert(SLIPOptions, at: .zero)
        return params
    }()
    internal var browser: OSCServiceBrowser? = nil
    
    public init() {}
    deinit {
        connection?.cancel()
    }
}

//MARK: - OSCNetworkClient Protocol

internal protocol NetworkClient: AnyObject {
    var connection: NWConnection? { get set }
    var parameters: NWParameters { get set }
    var browser: OSCServiceBrowser? { get set }
}

public extension OSCClient {
    func connect(endpoint: NWEndpoint) {
        guard let client = self as? NetworkClient else {
            fatalError("Adoption of OSCClient requires additional adoptance of NetworkClient")
        }
        
        client.connection = NWConnection(to: endpoint, using: client.parameters)
        setupConnection()
    }
    
    func connect(host: NWEndpoint.Host, port: NWEndpoint.Port) {
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        connect(endpoint: endpoint)
    }
    
    func connect(serviceName: String, timeout: TimeInterval? = nil) {
        guard let client = self as? NetworkClient else {
            fatalError("Adoption of OSCClient requires additional adoptance of NetworkClient")
        }
        
        client.browser = OSCServiceBrowser(serviceType: serviceType, parameters: client.parameters)
        client.browser?.start(timeout: timeout) { [weak self, weak client] results, error in
            guard error == nil else {
                client?.browser?.cancel()
                self?.delegate?.connectionStateChange(.failed(error!))
                return
            }
            
            guard let results = results,
                  let match = results.firstMatch(serviceName: serviceName) else {
                return
            }
            
            client?.browser?.cancel()
            self?.connect(endpoint: match.endpoint)
        }
    }
    
    func disconnect() {
        guard let client = self as? NetworkClient else {
            fatalError("Adoption of OSCClient requires additional adoptance of NetworkClient")
        }
        
        client.connection?.cancel()
    }
    
    func send(_ message: OSCMessage, completion: @escaping (NWError?)->Swift.Void) throws {
        try send(element: message, completion: completion)
    }
    
    func send(_ bundle: OSCBundle, completion: @escaping (NWError?)->Swift.Void) throws {
        try send(element: bundle, completion: completion)
    }
    
    internal func send(element: OSCBundleElement, completion: @escaping (NWError?)->Swift.Void) throws {
        guard let client = self as? NetworkClient else {
            fatalError("Adoption of OSCClient requires additional adoptance of NetworkClient")
        }
        
        guard let connection = client.connection,
              connection.state == .ready else {
            throw OSCNetworkingError.notConnected
        }
        
        let packet = try element.packet()
        connection.send(content: packet, completion: .contentProcessed( { error in
            completion(error)
        }))
    }
    
    fileprivate func setupConnection() {
        guard let client = self as? NetworkClient else {
            fatalError("Adoption of OSCClient requires additional adoptance of NetworkClient")
        }
        
        guard let connection = client.connection else {
            return
        }
        
        connection.stateUpdateHandler = { [weak self, weak client] (state) in
            switch state {
            case .failed(let error):
                OSCNetworkLogger.debug("\(connection.debugDescription) failed: \(error.debugDescription)")
                fallthrough
            case .cancelled:
                client?.connection = nil
                
            default:
                break
            }
            
            self?.delegate?.connectionStateChange(state)
        }
        
        OSCNetworkLogger.debug("Starting connection to: \(connection.debugDescription)")
        connection.start(queue: .main)
    }
}

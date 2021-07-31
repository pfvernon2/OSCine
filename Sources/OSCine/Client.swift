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

//MARK: - OSCClientUDP

///UDP based OSC client
public class OSCClientUDP: OSCNetworkClient {
    weak var delegate: OSCClientDelegate? = nil
    var serviceType: String = kOSCServiceTypeUDP
    
    internal var connection: NWConnection? = nil
    internal var parameters: NWParameters = {
        var params: NWParameters = .udp
        params.includePeerToPeer = true
        return params
    }()
    internal var browser: OSCServiceBrowser? = nil

    deinit {
        connection?.cancel()
    }
}

//MARK: - OSCClientTCP

///TCP based OSC client
public class OSCClientTCP: OSCNetworkClient {
    weak var delegate: OSCClientDelegate? = nil
    var serviceType: String = kOSCServiceTypeTCP
    
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

    deinit {
        connection?.cancel()
    }
}

//MARK: - OSCNetworkClient Protocol

protocol OSCNetworkClient: AnyObject {
    var delegate: OSCClientDelegate? { get set }
    var serviceType: String { get set }

    var connection: NWConnection? { get set }
    var parameters: NWParameters { get set }
    var browser: OSCServiceBrowser? { get set }
    
    func connect(endpoint: NWEndpoint)
    func connect(host: NWEndpoint.Host, port: NWEndpoint.Port)
    func connect(serviceName: String, timeout: TimeInterval?)
    
    func disconnect()
    
    func send(_ packetContents: OSCPacketContents, completion: @escaping (NWError?)->Swift.Void) throws
}

extension OSCNetworkClient {
    func connect(endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: parameters)
        setupConnection()
    }
    
    func connect(host: NWEndpoint.Host, port: NWEndpoint.Port) {
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        connect(endpoint: endpoint)
    }
    
    func connect(serviceName: String, timeout: TimeInterval?) {
        browser = OSCServiceBrowser(serviceType: serviceType, parameters: parameters)
        browser?.start(timeout: timeout) { [weak self] results, error in
            guard error == nil else {
                self?.browser?.cancel()
                self?.delegate?.connectionStateChange(.failed(error!))
                return
            }
            
            guard let results = results,
                  let match = results.firstMatch(serviceName: serviceName) else {
                return
            }
            
            self?.browser?.cancel()
            self?.connect(endpoint: match.endpoint)
        }
    }
    
    func disconnect() {
        connection?.cancel()
    }
    
    func send(_ packetContents: OSCPacketContents, completion: @escaping (NWError?)->Swift.Void) throws {
        guard let connection = connection, connection.state == .ready else {
            throw OSCNetworkingError.notConnected
        }
        
        let packet = try OSCPacket(packetContents: packetContents)
        connection.send(content: packet, completion: .contentProcessed( { error in
            completion(error)
        }))
    }
    
    fileprivate func setupConnection() {
        guard let connection = connection else {
            return
        }
        
        connection.stateUpdateHandler = { [weak self] (state) in
            switch state {
            case .failed(let error):
                OSCNetworkLogger.debug("\(connection.debugDescription) failed: \(error.debugDescription)")
                fallthrough
            case .cancelled:
                self?.connection = nil
                
            default:
                break
            }
            
            self?.delegate?.connectionStateChange(state)
        }
        
        OSCNetworkLogger.debug("Starting connection to: \(connection.debugDescription)")
        connection.start(queue: .main)
    }
}

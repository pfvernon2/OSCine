//
//  Client.swift
//  
//
//  Created by Frank Vernon on 6/30/21.
//

import Foundation
import Network

//MARK: - OSCNetworkClientDelegate

public protocol OSCNetworkClientDelegate: AnyObject {
    func connectionStateChange(_ state: NWConnection.State)
}

//MARK: - OSCNetworkClient Protocol

protocol OSCNetworkClient: AnyObject {
    var connection: NWConnection? { get set }
    var parameters: NWParameters { get set }
    var serviceType: String { get set }
    var browser: OSCServiceBrowser? { get set }

    var delegate: OSCNetworkClientDelegate? { get set }

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

//MARK: - OSCClientUDP

public class OSCClientUDP: OSCNetworkClient {
    internal var serviceType: String = kOSCServiceTypeUDP
    weak var delegate: OSCNetworkClientDelegate? = nil
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

public class OSCClientTCP: OSCNetworkClient {
    internal var serviceType: String = kOSCServiceTypeTCP
    weak var delegate: OSCNetworkClientDelegate? = nil
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

//MARK: - OSCBrowser

public class OSCServiceBrowser {
    var serviceType: String
    internal var parameters: NWParameters
    internal var browser: NWBrowser?
    internal var browserTimer: Timer?

    public init(serviceType: String, parameters: NWParameters) {
        self.serviceType = serviceType
        self.parameters = parameters
    }

    deinit {
        cancel()
    }
    
    public func start(timeout: TimeInterval? = nil,
                      _ updates: @escaping (Set<NWBrowser.Result>?, NWError?)->Swift.Void) {
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser?.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .failed(let error):
                OSCNetworkLogger.debug("Browser failed: \(error.localizedDescription)")
                self?.cancel()
                updates(nil, error)
                
            case .cancelled:
                self?.browser = nil
                self?.cancel()

            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { results, changes in
            self.browserTimer?.invalidate()
            updates(results, nil)
        }
        
        // Start browsing and ask for updates on the main queue.
        OSCNetworkLogger.debug("Starting browser for: \(self.browser?.debugDescription ?? "?")")
        browser?.start(queue: .main)
        
        //start the browser timer if requested
        if let timeout = timeout {
            browserTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] timer in
                self?.cancel()
                updates(nil, NWError.posix(POSIXErrorCode(rawValue: ETIMEDOUT)!))
            }
            browserTimer?.tolerance = 0.25
        }
    }
    
    public func cancel() {
        browser?.cancel()
        browserTimer?.invalidate()
        browserTimer = nil
    }
}

//MARK: - NWBrowserResultSet

typealias NWBrowserResultSet = Set<NWBrowser.Result>
extension NWBrowserResultSet {
    //Utility to return first instance of service matching service name
    func firstMatch(serviceName: String) -> NWBrowser.Result? {
        first {
            guard case let NWEndpoint.service(name: name, type: _, domain: _, interface: _) = $0.endpoint else {
                return false
            }
            
            return name == serviceName
        }
    }
}

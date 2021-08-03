//
//  Multicast.swift
//  
//
//  Created by Frank Vernon on 7/18/21.
//

import Foundation
import Network

//MARK: - OSCMulticastClientServerDelegate

///Delegate for notifications of network state change of the mulitcast client server
public protocol OSCMulticastClientServerDelegate: AnyObject {
    func groupStateChange(state: NWConnectionGroup.State)
}

//MARK: - OSCMulticastClientServer

public class OSCMulticastClientServer {
    weak public var delegate: OSCMulticastClientServerDelegate? = nil
    
    internal var group: NWConnectionGroup? = nil
    internal var parameters: NWParameters = {
        var params: NWParameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true
        return params
    }()
    
    internal var manager: OSCConnectionManager = OSCConnectionManager()
    
    internal let sendQueue = DispatchQueue(label: "com.cyberdev.oscmulticastclientserver", qos: .utility)
    internal var sendSemaphore: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    public init() {}
    deinit {
        cancel()
    }
    
    public func listen(on address: NWEndpoint.Host, port: NWEndpoint.Port) throws {
        try listen(on: .hostPort(host: address, port: port))
    }
    
    public func listen(on endpoint: NWEndpoint) throws {
        let multicast = try NWMulticastGroup(for: [endpoint])
        group = NWConnectionGroup(with: multicast, using: parameters)
        
        group?.stateUpdateHandler = { [weak self] (state) in
            switch state {
            case .cancelled:
                self?.group = nil
                self?.manager.cancelAll()
                
            default:
                break
            }
            
            self?.delegate?.groupStateChange(state: state)
        }
        
        group?.setReceiveHandler(maximumMessageSize: NWProtocolUDP.maxDatagramSize,
                                 rejectOversizedMessages: true) { [weak self] (message, content, isComplete) in
            if isComplete, let content = content, let packet = try? content.parseOSCPacket() {
                self?.manager.addressSpace.dispatch(packet: packet)
            } else if let connection = message.extractConnection() {
                self?.manager.add(connection: connection)
            }
        }
        
        group?.start(queue: .main)
    }
    
    public func cancel() {
        group?.cancel()
        group = nil
    }
    
    public func register(methods: [OSCMethod]) throws {
        try manager.addressSpace.register(methods: methods)
    }
    
    public func register(method: OSCMethod) throws {
        try manager.addressSpace.register(method: method)
    }
    
    public func deregister(method: OSCMethod) {
        manager.addressSpace.deregister(method: method)
    }
    
    public func deregisterAll() {
        manager.addressSpace.removeAll()
    }
    
    public func send(_ message: OSCMessage, completion: @escaping (NWError?)->Swift.Void) throws {
        try send(packetContents: message, completion: completion)
    }
    
    public func send(_ bundle: OSCBundle, completion: @escaping (NWError?)->Swift.Void) throws {
        try send(packetContents: bundle, completion: completion)
    }
    
    internal func send(packetContents: OSCPacketContents, completion: @escaping (NWError?)->Swift.Void) throws {
        guard let group = group, group.state == .ready else {
            throw OSCNetworkingError.notConnected
        }
        
        let packet = try OSCPacket(packetContents: packetContents)
        
        //queue sends as we potentially block waiting on previous send
        sendQueue.async {
            //Apple recommends serializing group send based on completion
            // https://developer.apple.com/news/?id=0oi77447
            self.sendSemaphore.wait()
            group.send(content: packet) { error in
                self.sendSemaphore.signal()
                completion(error)
            }
        }
    }
}

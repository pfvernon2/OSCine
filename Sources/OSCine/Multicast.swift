//
//  Multicast.swift
//  
//
//  Created by Frank Vernon on 7/18/21.
//

import Foundation
import Network

//MARK: - OSCMulticastClientServerDelegate

public protocol OSCMulticastClientServerDelegate: AnyObject {
    func groupStateChange(state: NWConnectionGroup.State)
}

//MARK: - OSCMulticastClientServer

public class OSCMulticastClientServer {
    weak var delegate: OSCMulticastClientServerDelegate? = nil

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
        
    func connect(to address: NWEndpoint.Host, port: NWEndpoint.Port) throws {
        try connect(to: .hostPort(host: address, port: port))
    }
    
    func connect(to endpoint: NWEndpoint) throws {
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
    }
    
    func start() throws {
        guard let group = group else {
            throw OSCNetworkingError.notConnected
        }
        
        //It appears that multicast objects must have receive handler set
        // before start or they will silently fail
        // so we are enforcing this here
        try receive()
        
        group.start(queue: .main)
    }
    
    internal func receive() throws {
        guard let group = group else {
            throw OSCNetworkingError.notConnected
        }

        group.setReceiveHandler(maximumMessageSize: NWProtocolUDP.maxDatagramSize,
                                 rejectOversizedMessages: true) { [weak self] (message, content, isComplete) in
            if isComplete, let content = content,
               let packet = try? OSCPacketFactory.decodeOSCPacket(packet: content) {
                self?.manager.addressSpace.dispatch(packet: packet)
            } else if let connection = message.extractConnection() {
                self?.manager.add(connection: connection)
            }
        }
    }
    
    func send(_ packetContents: OSCPacketContents, completion: @escaping (NWError?)->Swift.Void) throws {
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
    
    func cancel() {
        group?.cancel()
    }
    
    deinit {
        cancel()
    }
}


public class OSCUDPClientServer {
    
}

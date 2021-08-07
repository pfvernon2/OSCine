//
//  Browser.swift
//  
//
//  Created by Frank Vernon on 7/30/21.
//

import Foundation
import Network

//MARK: - OSCServiceBrowser

///Simple Bonjour browser with optional timeout.
///
///This is primarly intended for internal use but may be useful if you want to present
///a list of available OSC servers rather than simply defaulting to the first available.
@available(watchOS 6.0, *)
public class OSCServiceBrowser {
    private (set) var serviceType: String
    
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
                OSCLogDebug("Browser failed: \(error.localizedDescription)")
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
        OSCLogDebug("Starting browser for: \(self.browser?.debugDescription ?? "?")")
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

@available(watchOS 6.0, *)
typealias NWBrowserResultSet = Set<NWBrowser.Result>

@available(watchOS 6.0, *)
extension NWBrowserResultSet {
    //Utility to return first instance of service matching requested service name
    func firstMatch(serviceName: String) -> NWBrowser.Result? {
        first {
            guard case let NWEndpoint.service(name: name, type: _, domain: _, interface: _) = $0.endpoint else {
                return false
            }
            
            return name == serviceName
        }
    }
}

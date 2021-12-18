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
///This class is primarly intended for internal use but may be useful if you plan to present
///a list of available OSC servers rather than simply defaulting to the first match.
public class OSCServiceBrowser {
    private (set) var serviceType: String
    
    internal var parameters: NWParameters
    internal var browser: NWBrowser?
    internal var browserTimer: Timer? {
        didSet {
            browserTimer?.tolerance = 0.25
        }
    }
    
    public init(serviceType: String, parameters: NWParameters) {
        self.serviceType = serviceType
        self.parameters = parameters
    }
    
    deinit {
        cancel()
    }
    
    public func start(timeout: TimeInterval? = nil,
                      _ updates: @escaping (Set<NWBrowser.Result>?, NWError?)->Swift.Void) {
        let newBrowser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        
        newBrowser.stateUpdateHandler = { [weak self] newState in
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
        
        newBrowser.browseResultsChangedHandler = { results, changes in
            self.browserTimer?.invalidate()
            updates(results, nil)
        }
                
        // Start browsing and ask for updates on the main queue.
        DispatchQueue.main.async {
            self.browser = newBrowser

            OSCLogDebug("Starting browser for: \(newBrowser.debugDescription)")
            newBrowser.start(queue: .main)
            
            //start the browser timer if requested
            if let timeout = timeout {
                self.browserTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] timer in
                    OSCLogDebug("Browser timer fired for: \(newBrowser.debugDescription)")
                    self?.cancel()
                    updates(nil, NWError.posix(POSIXErrorCode.ETIMEDOUT))
                }
            }
        }
    }
    
    public func cancel() {
        browser?.cancel()
        browser = nil
        browserTimer?.invalidate()
        browserTimer = nil
    }
}

//MARK: - NWBrowserResultSet

typealias NWBrowserResultSet = Set<NWBrowser.Result>

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

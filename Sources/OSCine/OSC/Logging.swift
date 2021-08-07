//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/7/21.
//

import Foundation

#if !os(watchOS)
import OSLog
#endif

//MARK: - Logging

#if !os(watchOS)
internal var OSCNetworkLogger: Logger = {
    Logger(subsystem: "com.cyberdev.OSCine",
           category: "network")
}()
#endif

internal func OSCLogDebug(_ message: String) {
    #if !os(watchOS)
        OSCNetworkLogger.debug("\(message)")
    #else
        print(message)
    #endif
}

internal func OSCLogError(_ message: String) {
    #if !os(watchOS)
        OSCNetworkLogger.error("\(message)")
    #else
        print(message)
    #endif
}

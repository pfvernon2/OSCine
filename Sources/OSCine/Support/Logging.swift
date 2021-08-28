//
//  File.swift
//  
//
//  Created by Frank Vernon on 8/7/21.
//

import Foundation
import OSLog

//MARK: - Logging

internal var OSCNetworkLogger: Logger = {
    Logger(subsystem: "com.cyberdev.OSCine",
           category: "network")
}()

internal func OSCLogDebug(_ message: String) {
    OSCNetworkLogger.debug("\(message)")
}

internal func OSCLogError(_ message: String) {
    OSCNetworkLogger.error("\(message)")
}

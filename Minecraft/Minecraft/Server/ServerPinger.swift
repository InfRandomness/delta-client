//
//  ServerPinger.swift
//  Minecraft
//
//  Created by Rohan van Klinken on 20/1/21.
//

import Foundation
import os

class ServerPinger: Hashable, ObservableObject {
  var logger: Logger
  var eventManager: EventManager
  var connection: ServerConnection
  
  var info: ServerInfo
  
  @Published var pingInfo: PingInfo? = nil
  
  init(_ serverInfo: ServerInfo) {
    self.eventManager = EventManager()
    self.info = serverInfo
    self.logger = Logger(for: type(of: self))
    self.connection = ServerConnection(host: serverInfo.host, port: serverInfo.port, eventManager: eventManager)
    
    self.connection.registerPacketHandlers(handlers: [
      .status: StatusHandler(serverPinger: self)
    ])
  }
  
  func ping() {
    pingInfo = nil
    connection.restart()
    eventManager.registerOneTimeEventHandler({ (event) in
      self.connection.handshake(nextState: .status, callback: {
        let statusRequest = StatusRequest()
        self.connection.sendPacket(statusRequest)
      })
    }, eventName: "connectionReady")
  }
  
  static func == (lhs: ServerPinger, rhs: ServerPinger) -> Bool {
    return lhs.info == rhs.info
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(info)
  }
}

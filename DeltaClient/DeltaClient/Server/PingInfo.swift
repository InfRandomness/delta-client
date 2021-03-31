//
//  PingInfo.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 13/12/20.
//

import Foundation

struct PingInfo: Hashable {
  var versionName: String
  var protocolVersion: Int
  var maxPlayers: Int
  var numPlayers: Int
  var description: String
  var modInfo: String
}

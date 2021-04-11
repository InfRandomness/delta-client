//
//  DestroyEntitiesPacket.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 14/2/21.
//

import Foundation

struct DestroyEntitiesPacket: ClientboundPacket {
  static let id: Int = 0x37
  
  var entityIds: [Int]

  init(from packetReader: inout PacketReader) throws {
    entityIds = []
    let count = packetReader.readVarInt()
    for _ in 0..<count {
      let entityId = packetReader.readVarInt()
      entityIds.append(entityId)
    }
  }
}
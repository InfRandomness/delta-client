import Foundation

/// A player input. On a laptop or desktop, this represents a key press.
public enum Input: Codable, CaseIterable {
  case moveForward
  case moveBackward
  case strafeLeft
  case strafeRight
  
  case jump
  case sneak
  case sprint
  
  case toggleDebugHUD
  case changePerspective

  case performGPUFrameCapture
  
  public var humanReadableLabel: String {
    switch self {
      case .moveForward:
        return "Move forward"
      case .moveBackward:
        return "Move backward"
      case .strafeLeft:
        return "Strafe left"
      case .strafeRight:
        return "Strafe right"
        
      case .jump:
        return "Jump"
      case .sneak:
        return "Sneak"
      case .sprint:
        return "Sprint"
        
      case .toggleDebugHUD:
        return "Toggle debug HUD"
      case .changePerspective:
        return "Change Perspective"

      case .performGPUFrameCapture:
        return "Perform GPU trace"
    }
  }
}

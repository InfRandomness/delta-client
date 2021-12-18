import SwiftUI
import DeltaCore

enum PlayState {
  case connecting
  case loggingIn
  case downloadingChunks(numberReceived: Int, total: Int)
  case playing
}

enum OverlayState {
  case menu
  case settings
}

final class RenderCoordinatorWrapper {
  var renderCoordinator: RenderCoordinatorProtocol?
}

struct PlayServerView: View {
  @EnvironmentObject var appState: StateWrapper<AppState>
  @ObservedObject var state = StateWrapper<PlayState>(initial: .connecting)
  @ObservedObject var overlayState = StateWrapper<OverlayState>(initial: .menu)
  
  @Binding var cursorCaptured: Bool
  
  var client: Client
  var inputDelegate: ClientInputDelegate
  var serverDescriptor: ServerDescriptor
  var renderCoordinatorWrapper = RenderCoordinatorWrapper()
  
  init(serverDescriptor: ServerDescriptor, resourcePack: ResourcePack, inputCaptureEnabled: Binding<Bool>, delegateSetter setDelegate: (InputDelegate) -> Void) {
    self.serverDescriptor = serverDescriptor
    client = Client(resourcePack: resourcePack)
    client.configuration.render = ConfigManager.default.config.render
    
    // Disable input when the cursor isn't captured (after player hits escape during play to get to menu)
    _cursorCaptured = inputCaptureEnabled
    
    // Setup input system
    inputDelegate = ClientInputDelegate(for: client)
    setDelegate(inputDelegate)
    
    // Register for client events
    client.eventBus.registerHandler(handleClientEvent(_:))
    
    // Setup plugins
    DeltaClientApp.pluginEnvironment.addEventBus(client.eventBus)
    DeltaClientApp.pluginEnvironment.handleWillJoinServer(server: serverDescriptor, client: client)
    
    // Connect to server
    joinServer(serverDescriptor)
  }
  
  func makeRenderCoordinator() -> RenderCoordinatorProtocol {
    if let renderCoordinator = renderCoordinatorWrapper.renderCoordinator {
      return renderCoordinator
    }
    
    var pluginRenderCoordinator: RenderCoordinatorProtocol? = nil
    for (plugin, _, _) in DeltaClientApp.pluginEnvironment.plugins.values {
      if let renderCoordinator = plugin.makeRenderCoordinator(client) {
        pluginRenderCoordinator = renderCoordinator
        break
      }
    }
    
    let renderCoordinator = pluginRenderCoordinator ?? RenderCoordinator(client)
    renderCoordinatorWrapper.renderCoordinator = renderCoordinator
    return renderCoordinator
  }
  
  func joinServer(_ descriptor: ServerDescriptor) {
    // Get the account to use
    guard let account = ConfigManager.default.config.selectedAccount else {
      log.error("Error, attempted to join server without a selected account.")
      DeltaClientApp.modalError("Please login and select an account before joining a server", safeState: .accounts)
      return
    }
    
    // Refresh the account (if Mojang) and then join the server
    ConfigManager.default.refreshSelectedAccount(onCompletion: { account in
      client.joinServer(
        describedBy: descriptor,
        with: account,
        onFailure: { error in
          log.error("Failed to join server: \(error)")
          DeltaClientApp.modalError("Failed to join server: \(error)", safeState: .serverList)
        })
    }, onFailure: { error in
      let message = "Failed to refresh Mojang account '\(account.username)': \(error)"
      log.error(message)
      DeltaClientApp.modalError(message, safeState: .serverList)
    })
  }
  
  func handleClientEvent(_ event: Event) {
    switch event {
      case let connectionFailedEvent as ConnectionFailedEvent:
        let serverName = serverDescriptor.host + (serverDescriptor.port != nil ? (":" + String(serverDescriptor.port!)) : "")
        DeltaClientApp.modalError("Connection to \(serverName) failed: \(connectionFailedEvent.networkError.localizedDescription)", safeState: .serverList)
      case _ as LoginStartEvent:
        state.update(to: .loggingIn)
      case _ as JoinWorldEvent:
        // Approximation of the number of chunks the server will send (used in progress indicator)
        let totalChunksToReceieve = Int(pow(Double(client.game.maxViewDistance * 2 + 3), 2))
        state.update(to: .downloadingChunks(numberReceived: 0, total: totalChunksToReceieve))
      case _ as World.Event.AddChunk:
        ThreadUtil.runInMain {
          if case let .downloadingChunks(numberReceived, total) = state.current {
            state.update(to: .downloadingChunks(numberReceived: numberReceived + 1, total: total))
          }
        }
      case _ as TerrainDownloadCompletionEvent:
        state.update(to: .playing)
      case let disconnectEvent as PlayDisconnectEvent:
        DeltaClientApp.modalError("Disconnected from server during play:\n\n\(disconnectEvent.reason)", safeState: .serverList)
      case let disconnectEvent as LoginDisconnectEvent:
        DeltaClientApp.modalError("Disconnected from server during login:\n\n\(disconnectEvent.reason)", safeState: .serverList)
      case let packetError as PacketHandlingErrorEvent:
        DeltaClientApp.modalError("Failed to handle packet with id 0x\(String(packetError.packetId, radix: 16)):\n\n\(packetError.error)", safeState: .serverList)
      case let packetError as PacketDecodingErrorEvent:
        DeltaClientApp.modalError("Failed to decode packet with id 0x\(String(packetError.packetId, radix: 16)):\n\n\(packetError.error)", safeState: .serverList)
      case let generalError as ErrorEvent:
        if let message = generalError.message {
          DeltaClientApp.modalError("\(message); \(generalError.error)")
        } else {
          DeltaClientApp.modalError("\(generalError.error)")
        }
      default:
        break
    }
  }
  
  func disconnect() {
    client.closeConnection()
    appState.update(to: .serverList)
  }
  
  var body: some View {
    Group {
      switch state.current {
        case .connecting:
          connectingView
        case .loggingIn:
          loggingInView
        case .downloadingChunks(let numberReceived, let total):
          VStack {
            Text("Downloading chunks...")
            HStack {
              ProgressView(value: Double(numberReceived) / Double(total))
              Text("\(numberReceived) of \(total)")
            }
            .frame(maxWidth: 200)
            Button("Cancel", action: disconnect)
              .buttonStyle(SecondaryButtonStyle())
              .frame(width: 150)
          }
        case .playing:
          ZStack {
            gameView
            overlayView
          }
      }
    }
  }
  
  var connectingView: some View {
    VStack {
      Text("Establishing connection...")
      Button("Cancel", action: disconnect)
        .buttonStyle(SecondaryButtonStyle())
        .frame(width: 150)
    }
  }
  
  var loggingInView: some View {
    VStack {
      Text("Logging in...")
      Button("Cancel", action: disconnect)
        .buttonStyle(SecondaryButtonStyle())
        .frame(width: 150)
    }
  }
  
  var gameView: some View {
    ZStack {
      // Renderer
      MetalView(renderCoordinator: makeRenderCoordinator())
        .opacity(cursorCaptured ? 1 : 0.2)
        .onAppear {
          inputDelegate.bind($cursorCaptured.onChange { newValue in
            // When showing overlay make sure menu is the first view
            if newValue == false {
              overlayState.update(to: .menu)
            }
          })
          
          inputDelegate.captureCursor()
        }
      
      // Cross hair
      if cursorCaptured {
        Image(systemName: "plus")
          .font(.system(size: 20))
          .blendMode(.difference)
      }
    }
  }
  
  var overlayView: some View {
    VStack {
      // In-game menu overlay
      if !cursorCaptured {
        switch overlayState.current {
          case .menu:
            // Invisible button for escape to exit menu. Because keyboard shortcuts aren't working with my custom button styles
            Button("Back to game", action: inputDelegate.captureCursor)
              .keyboardShortcut(.escape, modifiers: [])
              .opacity(0)
            
            VStack {
              Button("Back to game", action: inputDelegate.captureCursor)
                .buttonStyle(PrimaryButtonStyle())
              Button("Settings", action: { overlayState.update(to: .settings) })
                .buttonStyle(SecondaryButtonStyle())
              Button("Disconnect", action: disconnect)
                .buttonStyle(SecondaryButtonStyle())
            }
            .frame(width: 200)
          case .settings:
            SettingsView(isInGame: true, client: client, onDone: {
              overlayState.update(to: .menu)
            })
        }
      }
    }
  }
}

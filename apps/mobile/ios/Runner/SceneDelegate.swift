import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    AssistantIntentDispatcher.shared.configureIfNeeded(
      rootViewController: window?.rootViewController
    )
    AssistantIntentDispatcher.shared.handleLaunchArguments(
      ProcessInfo.processInfo.arguments
    )
    if let url = connectionOptions.urlContexts.first?.url {
      AssistantIntentDispatcher.shared.handle(url: url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    AssistantIntentDispatcher.shared.configureIfNeeded(
      rootViewController: window?.rootViewController
    )
    guard let url = URLContexts.first?.url else {
      super.scene(scene, openURLContexts: URLContexts)
      return
    }
    if url.scheme?.lowercased() != "babyai" {
      super.scene(scene, openURLContexts: URLContexts)
      return
    }
    AssistantIntentDispatcher.shared.handle(url: url)
  }
}

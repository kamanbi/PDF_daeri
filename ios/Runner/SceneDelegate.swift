import Flutter
import UIKit

/// 다른 앱(카카오톡·메일·파일)에서 PDF를 "PDF 대리로 열기" 했을 때 URL을 받아 intent 채널로 넘긴다.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts { PlatformChannels.deliver(context.url) }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts { PlatformChannels.deliver(context.url) }
  }
}

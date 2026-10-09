import HistodexCore
import HistodexInterface
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    static var archiveStore: ArchiveStore?
    static var archiveError: Error?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do {
            let root: URL
            #if DEBUG
            if let path = ProcessInfo.processInfo.environment["HISTODEX_ARCHIVE_PATH"] { root = URL(fileURLWithPath: path) }
            else { root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Histodex") }
            #else
            root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Histodex")
            #endif
            Self.archiveStore = try ArchiveStore(root: root)
        } catch { Self.archiveError = error }
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Archive", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var recordsConversationID: String?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene); self.window = window
        let activity = connectionOptions.userActivities.first ?? session.stateRestorationActivity
        let recordsID = activity?.userInfo?["recordsConversationID"] as? String
        recordsConversationID = recordsID
        if let store = AppDelegate.archiveStore {
            let root = ArchiveRootController(store: store, scope: recordsID == nil ? .conversation : .allRecords)
            root.onConversationTitleChanged = { [weak scene] title in scene?.title = recordsID == nil ? title : "Archive Records · " + title }
            root.onOpenRecords = { id in
                let activity = NSUserActivity(activityType: "com.lloydME.Histodex.records")
                activity.userInfo = ["recordsConversationID": id]
                UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil)
            }
            window.rootViewController = root
            scene.title = recordsID == nil ? "Histodex" : "Archive Records"
            scene.sizeRestrictions?.minimumSize = CGSize(width: 850, height: 550)
            #if targetEnvironment(macCatalyst)
            scene.titlebar?.titleVisibility = .hidden
            scene.titlebar?.toolbar = nil
            #endif
            if let recordsID { root.openConversation(recordsID) }
        } else {
            let error = UIViewController(); error.view.backgroundColor = .systemBackground
            let text = UITextView(); text.isEditable = false; text.text = AppDelegate.archiveError?.localizedDescription ?? "Unable to open the archive."
            text.frame = error.view.bounds; text.autoresizingMask = [.flexibleWidth, .flexibleHeight]; error.view.addSubview(text)
            window.rootViewController = error
        }
        window.makeKeyAndVisible()
    }
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        guard let recordsConversationID else { return nil }
        let activity = NSUserActivity(activityType: "com.lloydME.Histodex.records")
        activity.userInfo = ["recordsConversationID": recordsConversationID]
        return activity
    }
}

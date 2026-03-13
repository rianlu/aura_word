import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let channelName = "com.aura.word/file_handler"
    private var pendingFilePath: String?
    private var eventSink: FlutterEventSink?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Setup MethodChannel
        let controller = window?.rootViewController as! FlutterViewController
        let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)
        
        methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            if call.method == "getInitialSharedFile" {
                result(self?.pendingFilePath)
                self?.pendingFilePath = nil
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        
        // Setup EventChannel for streaming file shares
        let eventChannel = FlutterEventChannel(name: "\(channelName)/events", binaryMessenger: controller.binaryMessenger)
        eventChannel.setStreamHandler(self)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Handle URL opening (e.g., from Files app, AirDrop, other apps)
    override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        handleIncomingFile(url: url)
        return true
    }
    
    private func handleIncomingFile(url: URL) {
        // Copy file to app's temp directory for safe access
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let tempFilePath = tempDir.appendingPathComponent("shared_backup_\(Date().timeIntervalSince1970).wcc")
        
        do {
            // Start accessing security-scoped resource
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Remove existing temp file if exists
            if fileManager.fileExists(atPath: tempFilePath.path) {
                try fileManager.removeItem(at: tempFilePath)
            }
            
            // Copy the file
            try fileManager.copyItem(at: url, to: tempFilePath)
            
            let filePath = tempFilePath.path
            
            // Send to Flutter
            if let sink = eventSink {
                sink(filePath)
            } else {
                pendingFilePath = filePath
            }
            
        } catch {
            print("Error handling incoming file: \(error)")
        }
    }
}

// MARK: - FlutterStreamHandler
extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        
        // Send pending file if any
        if let pending = pendingFilePath {
            events(pending)
            pendingFilePath = nil
        }
        
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

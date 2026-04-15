import AppKit
import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ChargeCapHelperProtocol.self)
        newConnection.exportedObject = HelperTool.shared
        newConnection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: ChargeCapHelperConfiguration.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()

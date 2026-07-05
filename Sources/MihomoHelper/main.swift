import Foundation
import MihomoShared

private final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MihomoHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private let delegate = HelperDelegate()
private let listener = NSXPCListener(machServiceName: MihomoHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()

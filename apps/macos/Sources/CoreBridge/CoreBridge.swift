import Foundation

import CoreFFI

public enum CoreBridge {
    public static func process(_ json: String) -> String {
        json.withCString { request in
            guard let result = cc_process(request) else { return "{\"ok\":false,\"error\":{\"code\":\"WORKER_INTERRUPTED\",\"message\":\"本地计算中断\",\"line\":0,\"column\":0}}" }
            defer { cc_free(result) }
            return String(cString: result)
        }
    }
}

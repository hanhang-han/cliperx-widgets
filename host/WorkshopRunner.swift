import Foundation
import JavaScriptCore

/// Compiled as a sandboxed helper executable, outside the SwiftUI application's Sources phase.
@main enum WorkshopRunner {
    static func main() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard input.count <= 524288,
                  let request = try JSONSerialization.jsonObject(with: input) as? [String: Any],
                  let script = request["script"] as? String, script.utf8.count <= 131072,
                  let context = request["context"] as? [String: Any],
                  let engine = JSContext() else { throw WorkshopError.invalid("Invalid runner input") }
            var scriptError: String?
            engine.exceptionHandler = { _, exception in scriptError = String((exception?.toString() ?? "JavaScript error").prefix(500)) }
            engine.evaluateScript(WorkshopScriptProtocol.bootstrap)
            engine.setObject(context, forKeyedSubscript: "__context" as NSString)
            engine.setObject(request["action"] ?? NSNull(), forKeyedSubscript: "__action" as NSString)
            engine.evaluateScript(script)
            if let scriptError { throw WorkshopError.invalid(scriptError) }
            let output = engine.evaluateScript(WorkshopScriptProtocol.evaluate)?.toString() ?? ""
            if let scriptError { throw WorkshopError.invalid(scriptError) }
            guard let data = output.data(using: .utf8), data.count <= 65536 else { throw WorkshopError.invalid("Result exceeds 64 KB") }
            let result = try JSONDecoder().decode(WorkshopResult.self, from: data)
            try result.view.validate()
            guard result.effects.count <= 4 else { throw WorkshopError.invalid("Too many effects") }
            FileHandle.standardOutput.write(data)
        } catch {
            let data = try? JSONSerialization.data(withJSONObject: ["error": String(error.localizedDescription.prefix(500))])
            FileHandle.standardOutput.write(data ?? Data())
            exit(1)
        }
    }
}

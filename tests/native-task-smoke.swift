import Foundation

@main
struct NativeTaskSmoke {
    static func main() throws {
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = try JSONDecoder().decode(WorkshopManifest.self, from: Data(contentsOf: manifestURL))
        try manifest.validate()
        let task = manifest.task!
        do {
            _ = try task.render(parameters: [:], question: "")
            preconditionFailure("Missing required parameter should fail")
        } catch is WorkshopError {}
        let literal = try task.render(parameters: ["product": "{{question}}", "severity": "{{parameters.product}}"], question: "$& {{parameters.product}}")
        precondition(literal.contains("你负责整理 {{question}} 的 Bug 单"))
        precondition(literal.contains("影响程度要求 {{parameters.product}}"))
        precondition(literal.hasSuffix("$& {{parameters.product}}"))
        let unknown = WorkshopTaskDefinition(input: task.input, parameters: task.parameters, prompt: "{{unknown}}", output: task.output)
        do {
            try unknown.validate()
            preconditionFailure("Unknown variable should fail")
        } catch is WorkshopError {}
        let appending = WorkshopTaskDefinition(input: task.input, parameters: task.parameters, prompt: "整理 {{parameters.product}}", output: task.output)
        let appended = try appending.render(parameters: ["product": "灵剪"], question: "附加内容")
        precondition(appended == "整理 灵剪\n\n用户补充\n附加内容")
        print("PASS API 4 decoding, required fields, unknown variables and literal rendering")
    }
}

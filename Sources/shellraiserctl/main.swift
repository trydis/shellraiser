import Foundation
import ShellraiserShimKit

/// `shellraiserctl` executable entry point.
@main
struct ShellraiserControlMain {
    /// Parses command-line arguments and exits with the control CLI status code.
    static func main() {
        let cli = ShellraiserControlCLI(controller: ShellraiserAppleScriptClient())
        let result = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))

        if !result.standardOutput.isEmpty {
            FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
        }
        if !result.standardError.isEmpty {
            FileHandle.standardError.write(Data(result.standardError.utf8))
        }

        exit(result.exitCode)
    }
}

import Foundation
import ShellraiserShimKit

/// `tmux` compatibility executable entry point.
@main
struct TmuxShimMain {
    /// Parses command-line arguments and exits with the tmux-compatible status code.
    static func main() {
        let cli = TmuxShimCLI(
            controller: ShellraiserAppleScriptClient(),
            stateStore: FileTmuxShimStateStore()
        )
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

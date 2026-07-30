import Foundation

enum TUNCommandBuilder {
    static func startCommand(
        corePath: String,
        configPath: String,
        logPath: String,
        pidPath: String,
        stopPath: String,
        reloadPath: String
    ) -> String {
        let launch = [
            shellQuote(corePath),
            "run -c",
            shellQuote(configPath),
            "< /dev/null >",
            shellQuote(logPath),
            "2>&1"
        ].joined(separator: " ")

        let child = "$realitylink_child"
        return [
            "umask 077",
            "realitylink_start() { \(launch) & realitylink_child=$!; /bin/echo \"\(child)\" > \(shellQuote(pidPath)); }",
            "realitylink_stop() { /bin/kill -TERM \"\(child)\" 2>/dev/null; wait \"\(child)\" 2>/dev/null; }",
            "trap 'realitylink_stop; exit 0' HUP INT TERM",
            "realitylink_start",
            "while true; do if /bin/test -e \(shellQuote(stopPath)); then realitylink_stop; exit 0; fi; if /bin/test -e \(shellQuote(reloadPath)); then /bin/rm -f \(shellQuote(reloadPath)); realitylink_stop; realitylink_start; fi; if ! /bin/kill -0 \"\(child)\" 2>/dev/null; then wait \"\(child)\"; exit $?; fi; /bin/sleep 0.25; done"
        ].joined(separator: "; ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

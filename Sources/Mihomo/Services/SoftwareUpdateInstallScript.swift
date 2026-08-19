import Foundation

enum SoftwareUpdateInstallScript {
    static func write(to tempRoot: URL) throws -> URL {
        let script = tempRoot.appendingPathComponent("install-update.sh")
        let body = """
        #!/bin/sh
        set -eu
        current="$1"
        candidate="$2"
        temp="$3"
        backup="${current}.previous-update"

        restore_backup() {
          /bin/rm -rf "$current"
          if [ -e "$backup" ]; then
            /bin/mv "$backup" "$current"
          fi
        }

        is_current_app_running() {
          executable="$current/Contents/MacOS/Mihomo"
          for pid in $(/usr/bin/pgrep -x "Mihomo" 2>/dev/null || true); do
            command=$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)
            case "$command" in
              "$executable"|"$executable "*) return 0 ;;
            esac
          done
          return 1
        }

        while is_current_app_running; do
          /bin/sleep 0.2
        done

        /bin/rm -rf "$backup"
        if [ -e "$current" ]; then
          /bin/mv "$current" "$backup"
        fi

        if ! /usr/bin/ditto "$candidate" "$current"; then
          restore_backup
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$current" >/dev/null 2>&1 || true

        if ! /usr/bin/codesign --verify --deep --strict "$current" >/dev/null 2>&1; then
          restore_backup
          exit 1
        fi

        /usr/bin/open "$current"
        /bin/rm -rf "$backup" "$temp"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}

import Foundation

/// Proceso escuchando un puerto, con su directorio de trabajo (sin resolver aún).
struct RawProc: Sendable {
    var name: String
    var port: Int
    var cwd: String
}

/// Detecta servidores host (corriendo con o sin Docker) vía lsof.
enum ProcessProbe {
    static func read() -> [RawProc] {
        // 1) listeners TCP: pid, comando, puerto (formato -F: p<pid> c<cmd> n<host:port>)
        let l = Shell.run("lsof -nP -iTCP -sTCP:LISTEN -FpcnP 2>/dev/null", timeout: 8)
        guard l.code == 0 else { return [] }
        struct L { var pid: String; var cmd: String; var port: Int }
        var listeners: [L] = []
        var pid = "", cmd = ""
        for line in l.out.split(separator: "\n") {
            let s = String(line); guard let tag = s.first else { continue }
            let val = String(s.dropFirst())
            switch tag {
            case "p": pid = val
            case "c": cmd = val
            case "n":
                // "*:3000", "127.0.0.1:5173", "[::1]:8080"
                if let portStr = val.split(separator: ":").last, let port = Int(portStr) {
                    listeners.append(L(pid: pid, cmd: cmd, port: port))
                }
            default: break
            }
        }
        guard !listeners.isEmpty else { return [] }

        // 2) cwd por pid (una sola llamada con todos los pids)
        let pids = Array(Set(listeners.map { $0.pid })).joined(separator: ",")
        let c = Shell.run("lsof -a -d cwd -nP -p \(pids) -Fn 2>/dev/null", timeout: 8)
        var cwdByPid: [String: String] = [:]
        var curPid = ""
        for line in c.out.split(separator: "\n") {
            let s = String(line); guard let tag = s.first else { continue }
            let val = String(s.dropFirst())
            if tag == "p" { curPid = val }
            else if tag == "n", cwdByPid[curPid] == nil { cwdByPid[curPid] = val }
        }

        // 3) combinar; solo procesos con cwd conocido
        var out: [RawProc] = []
        for lst in listeners {
            guard let cwd = cwdByPid[lst.pid] else { continue }
            out.append(RawProc(name: lst.cmd, port: lst.port, cwd: cwd))
        }
        return out
    }
}

/// Descubre las raíces de proyecto bajo ~/Dev (dirs con .git), hasta 2 niveles.
enum ProjectProbe {
    static func devRoots() -> [String] {
        let home = NSHomeDirectory()
        let dev = "\(home)/Dev"
        let fm = FileManager.default
        var roots: [String] = []
        func scan(_ dir: String, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for e in entries where !e.hasPrefix(".") {
                let p = "\(dir)/\(e)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
                if fm.fileExists(atPath: "\(p)/.git") {
                    roots.append(p)
                } else if depth > 0 {
                    scan(p, depth: depth - 1)   // grupos como liftit/, beu/, hacks/
                }
            }
        }
        scan(dev, depth: 1)
        return roots
    }
}

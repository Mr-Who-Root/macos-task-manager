import Darwin
import Foundation

/// A TCP port a process is listening on.
struct ListeningPort: Identifiable, Hashable, Sendable {
    let pid: Int32
    let port: Int
    /// Bound to the loopback address only, so other computers can't connect.
    let localOnly: Bool

    var id: String { "\(pid):\(port)" }
}

enum NetworkPorts {
    /// Listening TCP sockets of the processes libproc lets us inspect (the current user's).
    /// Other users' processes, including system services, need administrator access.
    static func listening() -> [ListeningPort] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        var sockets: [(pid: Int32, port: Int, loopback: Bool)] = []
        for pid in pids.prefix(Int(bytes)) where pid > 0 {
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.stride)
            let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
            guard filled > 0 else { continue }
            for fd in fds.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                var info = socket_fdinfo()
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size)) > 0,
                      info.psi.soi_kind == SOCKINFO_TCP else { continue }
                let tcp = info.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }
                let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
                sockets.append((pid, port, isLoopback(tcp.tcpsi_ini)))
            }
        }
        return merge(sockets)
    }

    /// One entry per process and port; IPv4 and IPv6 sockets on the same port are merged, and the
    /// port counts as local only if every socket is bound to loopback.
    static func merge(_ sockets: [(pid: Int32, port: Int, loopback: Bool)]) -> [ListeningPort] {
        var merged: [String: ListeningPort] = [:]
        for socket in sockets {
            let key = "\(socket.pid):\(socket.port)"
            let localOnly = (merged[key]?.localOnly ?? true) && socket.loopback
            merged[key] = ListeningPort(pid: socket.pid, port: socket.port, localOnly: localOnly)
        }
        return merged.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func isLoopback(_ address: in_sockinfo) -> Bool {
        if address.insi_vflag & 0x2 != 0 {   // INI_IPV6
            var v6 = address.insi_laddr.ina_6
            return withUnsafeBytes(of: &v6) { bytes in bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1 }
        }
        let v4 = UInt32(bigEndian: address.insi_laddr.ina_46.i46a_addr4.s_addr)
        return v4 >> 24 == 127
    }
}

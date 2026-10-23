import Foundation
import Darwin

/// A kernel-held, per-user lock shared by all copies of RadioBar.
/// Keep the file in place: unlinking it could let two processes lock different inodes.
final class SingleInstanceLock {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    static func acquire(at file: URL) throws -> SingleInstanceLock? {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return SingleInstanceLock(descriptor: fd)
    }

    deinit { close(descriptor) } // Also released by the kernel on crash / forced quit.
}

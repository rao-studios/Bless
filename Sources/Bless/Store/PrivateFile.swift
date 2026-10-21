//
//  PrivateFile.swift
//  Bless
//
//  Created by Ritesh Pakala on 10/20/26.
//  Copyright © 2026 Rao Studios LLC.
//
//  WHAT: Files only their owner can read: directories made 0700, files 0600, whole-file writes
//        that land atomically (a temporary file beside the target, flushed, then renamed over
//        it), and appends flushed to disk before they return.
//

import Foundation

enum PrivateFile {
    static func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            throw BlessError.store("cannot create \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Creates an empty 0600 file if none is there.
    static func touch(_ url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw failure("open", url) }
        close(fd)
    }

    static func writeAtomically(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.lowercased()).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw failure("open", temporary) }
        do {
            try writeAll(data, to: fd, url: temporary)
            guard fsync(fd) == 0 else { throw failure("flush", temporary) }
            close(fd)
        } catch {
            close(fd)
            unlink(temporary.path)
            throw error
        }
        guard rename(temporary.path, url.path) == 0 else {
            unlink(temporary.path)
            throw failure("rename", url)
        }
    }

    static func append(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw failure("open", url) }
        defer { close(fd) }
        try writeAll(data, to: fd, url: url)
        guard fsync(fd) == 0 else { throw failure("flush", url) }
    }

    static func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw BlessError.store("cannot read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32, url: URL) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw failure("write", url)
                }
                offset += written
            }
        }
    }

    private static func failure(_ verb: String, _ url: URL) -> BlessError {
        .store("cannot \(verb) \(url.lastPathComponent): \(String(cString: strerror(errno)))")
    }
}

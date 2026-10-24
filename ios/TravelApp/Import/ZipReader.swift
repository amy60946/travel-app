import Compression
import Foundation

/// Küçük bir .zip okuyucu. Instagram, TikTok ve Google veri dosyaları .zip
/// olarak iner; kullanıcı açmak zorunda kalmasın diye uygulama kendisi açar.
/// "Sıkıştırmasız" ve "deflate" yeterli; büyük (zip64) arşivler de okunur.
struct ZipReader {
    struct Entry: Equatable {
        let path: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    let data: Data
    let entries: [Entry]

    init?(data: Data) {
        guard let entries = Self.readEntries(data) else { return nil }
        self.data = data
        self.entries = entries
    }

    /// Bir dosyanın içeriği; bozuk ya da desteklenmeyen sıkıştırmada nil.
    func contents(of entry: Entry) -> Data? {
        let header = entry.localHeaderOffset
        guard data.number(at: header, size: 4) == 0x04034b50,
              let nameLength = data.number(at: header + 26, size: 2),
              let extraLength = data.number(at: header + 28, size: 2) else { return nil }
        let start = header + 30 + nameLength + extraLength
        guard entry.compressedSize >= 0, start + entry.compressedSize <= data.count else { return nil }
        let base = data.startIndex + start
        let compressed = data.subdata(in: base ..< base + entry.compressedSize)
        switch entry.method {
        case 0: return compressed
        case 8: return Self.inflate(compressed, size: entry.size)
        default: return nil
        }
    }

    private static func inflate(_ input: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        guard !input.isEmpty else { return nil }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let destination = out.bindMemory(to: UInt8.self).baseAddress,
                      let bytes = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB, başlıksız (raw) deflate okur; zip de bunu kullanır.
                return compression_decode_buffer(destination, size, bytes, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? output : nil
    }

    private static func readEntries(_ data: Data) -> [Entry]? {
        // Dosyanın sonundaki "merkez dizin sonu" kaydını bul (arkasında en fazla 64 KB yorum olabilir).
        guard data.count >= 22 else { return nil }
        let lowest = max(0, data.count - 22 - 65_535)
        var end = data.count - 22
        while end >= lowest, data.number(at: end, size: 4) != 0x06054b50 { end -= 1 }
        guard end >= lowest,
              var count = data.number(at: end + 10, size: 2),
              var cursor = data.number(at: end + 16, size: 4) else { return nil }

        // zip64: gerçek sayı ve konum ayrı bir kayıtta durur.
        if count == 0xFFFF || cursor == 0xFFFF_FFFF,
           data.number(at: end - 20, size: 4) == 0x07064b50,
           let record = data.number(at: end - 20 + 8, size: 8),
           data.number(at: record, size: 4) == 0x06064b50,
           let realCount = data.number(at: record + 32, size: 8),
           let realOffset = data.number(at: record + 48, size: 8) {
            count = realCount
            cursor = realOffset
        }

        var entries: [Entry] = []
        for _ in 0..<min(count, 1_000_000) {
            guard data.number(at: cursor, size: 4) == 0x02014b50,
                  let method = data.number(at: cursor + 10, size: 2),
                  var compressed = data.number(at: cursor + 20, size: 4),
                  var size = data.number(at: cursor + 24, size: 4),
                  let nameLength = data.number(at: cursor + 28, size: 2),
                  let extraLength = data.number(at: cursor + 30, size: 2),
                  let commentLength = data.number(at: cursor + 32, size: 2),
                  var local = data.number(at: cursor + 42, size: 4),
                  cursor + 46 + nameLength <= data.count else { break }

            let nameStart = data.startIndex + cursor + 46
            let nameData = data.subdata(in: nameStart ..< nameStart + nameLength)
            let path = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""

            // zip64 ek alanı: 0xFFFFFFFF olan değerlerin gerçeği burada, bu sırayla.
            if size == 0xFFFF_FFFF || compressed == 0xFFFF_FFFF || local == 0xFFFF_FFFF {
                var field = cursor + 46 + nameLength
                let fieldsEnd = field + extraLength
                while field + 4 <= fieldsEnd,
                      let id = data.number(at: field, size: 2),
                      let length = data.number(at: field + 2, size: 2) {
                    if id == 1 {
                        var position = field + 4
                        if size == 0xFFFF_FFFF, let value = data.number(at: position, size: 8) {
                            size = value
                            position += 8
                        }
                        if compressed == 0xFFFF_FFFF, let value = data.number(at: position, size: 8) {
                            compressed = value
                            position += 8
                        }
                        if local == 0xFFFF_FFFF, let value = data.number(at: position, size: 8) {
                            local = value
                        }
                        break
                    }
                    field += 4 + length
                }
            }

            if !path.hasSuffix("/") {
                entries.append(Entry(path: path, method: method, compressedSize: compressed,
                                     size: size, localHeaderOffset: local))
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }
}

private extension Data {
    /// `offset`'teki küçük-sonlu (little-endian) sayı; dosya dışına taşarsa nil.
    func number(at offset: Int, size: Int) -> Int? {
        guard offset >= 0, offset + size <= count else { return nil }
        var value: UInt64 = 0
        for index in (0..<size).reversed() {
            value = value << 8 | UInt64(self[startIndex + offset + index])
        }
        return Int(clamping: value)
    }
}

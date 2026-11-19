//
//  MiniZip.swift
//  ReaderApp
//
//  极小的 ZIP 写入器（只做「存储」不压缩），用来把在线漫画图打成 CBZ。
//  自己写是为了避开 ZIPFoundation 写入 API 的版本差异，读包仍用 ZIPFoundation。
//

import Foundation

enum MiniZip {

    static func make(entries: [(name: String, data: Data)]) -> Data {
        var local = Data()
        var central = Data()
        var crcTable = CRC32.table

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = CRC32.compute(entry.data, table: &crcTable)
            let size = UInt32(entry.data.count)
            let offset = UInt32(local.count)

            local.appendUInt32(0x0403_4b50)
            local.appendUInt16(20)                    // version needed
            local.appendUInt16(0x0800)                // UTF-8 文件名
            local.appendUInt16(0)                     // 存储
            local.appendUInt16(0)                     // time
            local.appendUInt16(0x21)                  // date: 1980-01-01
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0)                     // extra
            local.append(nameData)
            local.append(entry.data)

            central.appendUInt32(0x0201_4b50)
            central.appendUInt16(20)                  // version made by
            central.appendUInt16(20)                  // version needed
            central.appendUInt16(0x0800)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0x21)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)                   // extra
            central.appendUInt16(0)                   // comment
            central.appendUInt16(0)                   // disk
            central.appendUInt16(0)                   // internal attrs
            central.appendUInt32(0)                   // external attrs
            central.appendUInt32(offset)
            central.append(nameData)
        }

        var output = local
        let centralOffset = UInt32(local.count)
        output.append(central)

        output.appendUInt32(0x0605_4b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(central.count))
        output.appendUInt32(centralOffset)
        output.appendUInt16(0)

        return output
    }

    // MARK: - CRC32

    enum CRC32 {
        static let table: [UInt32] = {
            var table = [UInt32](repeating: 0, count: 256)
            for i in 0..<256 {
                var c = UInt32(i)
                for _ in 0..<8 {
                    c = (c & 1) == 1 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
                }
                table[i] = c
            }
            return table
        }()

        static func compute(_ data: Data, table: inout [UInt32]) -> UInt32 {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in data {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
            return crc ^ 0xFFFF_FFFF
        }
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

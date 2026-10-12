module Ps2IsoFixture
  def ps2_iso_bytes(boot_name: "SLUS_213.55", nested: false)
    bytes = "\0".b * (24 * 2048)
    bytes[16 * 2048, 7] = "\x01CD001\x01".b
    bytes[16 * 2048 + 128, 4] = [ 2048, 2048 ].pack("vn")
    root = iso_record("\0".b, 20, 2048, directory: true)
    bytes[16 * 2048 + 156, root.bytesize] = root
    elf = "\x7FELF\x01\x01\x01\0".b + "\0".b * 44 + [ 0x12345678, 0xAABBCCDD ].pack("V*") + "\xBB".b
    boot_path = nested ? "BOOT\\#{boot_name}" : boot_name
    cnf = "BOOT2 = cdrom0:\\#{boot_path};1\r\nVER = 1.00\r\n"
    entries = root + iso_record("\x01".b, 20, 2048, directory: true) + iso_record("SYSTEM.CNF;1", 21, cnf.bytesize)
    if nested
      entries += iso_record("BOOT", 23, 2048, directory: true)
      subdirectory = iso_record("\0".b, 23, 2048, directory: true) + iso_record("\x01".b, 20, 2048, directory: true) + iso_record("#{boot_name};7", 22, elf.bytesize)
      bytes[23 * 2048, subdirectory.bytesize] = subdirectory
    else
      entries += iso_record("#{boot_name};7", 22, elf.bytesize)
    end
    bytes[20 * 2048, entries.bytesize] = entries
    bytes[21 * 2048, cnf.bytesize] = cnf
    bytes[22 * 2048, elf.bytesize] = elf
    bytes
  end

  def fixture_crc
    0x464C457F ^ 0x00010101 ^ 0x12345678 ^ 0xAABBCCDD
  end

  def iso_record(name, sector, size, directory: false)
    length = 33 + name.bytesize + (name.bytesize.even? ? 1 : 0)
    record = "\0".b * length
    record.setbyte(0, length)
    record[2, 8] = [ sector, sector ].pack("VN")
    record[10, 8] = [ size, size ].pack("VN")
    record.setbyte(25, directory ? 2 : 0)
    record[28, 4] = [ 1, 1 ].pack("vn")
    record.setbyte(32, name.bytesize)
    record[33, name.bytesize] = name
    record
  end
end

# Read-only ISO9660 identification matching PCSX2 2.8.2 CDVD.cpp and
# Elfheader.cpp: the game CRC is XOR of the boot ELF's little-endian words,
# not a CRC32 of the disc. No disc contents are executed or extracted.
class Ps2DiscIdentity
  class Error < StandardError; end

  SECTOR_SIZE = 2048
  DIRECTORY_BUDGET = 4 * 1024 * 1024
  ELF_LIMIT = 64 * 1024 * 1024
  Identity = Data.define(:serial, :crc) do
    def settings_filename
      "#{serial.empty? ? '' : "#{serial}_"}#{format('%08X', crc)}.ini"
    end
  end

  def self.read(path)
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      raise Error, "The disc is not a regular, unlinked ISO." unless file.stat.file? && file.stat.nlink == 1
      new(file).read
    end
  end

  def initialize(file)
    @file = file
    @size = file.stat.size
    @directory_bytes = 0
  end

  def read
    pvd = bytes_at(16 * SECTOR_SIZE, SECTOR_SIZE)
    raise Error, "The disc has no supported ISO9660 primary volume." unless pvd.start_with?("\x01CD001\x01".b) && pvd.byteslice(128, 2).unpack1("v") == SECTOR_SIZE
    @root = record(pvd.byteslice(156, pvd.getbyte(156)))
    cnf = locate("SYSTEM.CNF")
    raise Error, "SYSTEM.CNF is too large." unless cnf[:size].between?(1, 64 * 1024)
    text = bytes_at(cnf[:offset], cnf[:size])
    boot = text.match(/^[ \t]*BOOT2[ \t]*=[ \t]*(cdrom0?:[^\r\n]+)[ \t]*\r?$/i)&.[](1)&.strip
    raise Error, "The disc has no supported PS2 BOOT2 executable." unless boot
    path = boot.sub(/\Acdrom0?:/i, "").sub(/;.*\z/, "").tr("\\", "/")
    elf = locate(path)
    raise Error, "The boot ELF exceeds the bounded identification limit." unless elf[:size].between?(52, ELF_LIMIT)
    raise Error, "The boot executable is not a little-endian PS2 ELF." unless bytes_at(elf[:offset], 7) == "\x7FELF\x01\x01\x01".b
    crc = 0
    offset = elf[:offset]
    remaining = elf[:size] / 4 * 4
    while remaining.positive?
      length = [ remaining, 64 * 1024 ].min
      bytes_at(offset, length).unpack("V*").each { |word| crc ^= word }
      offset += length
      remaining -= length
    end
    raise Error, "The boot ELF has a zero PCSX2 game CRC." if crc.zero?
    filename = path.split("/").last
    serial = filename.match?(/\A[A-Za-z0-9]{4}[_-][0-9]{3}\.[0-9]{2}[A-Za-z0-9._-]*\z/) ? filename.delete(".").tr("_", "-").upcase : ""
    Identity.new(serial: serial, crc: crc)
  end

  private

  def locate(path)
    parts = path.split("/").reject(&:empty?)
    raise Error, "The ISO executable path is unsupported." unless parts.size.between?(1, 16) && parts.none? { |part| part == "." || part == ".." || part.match?(/[\x00-\x1F]/) }
    directory = @root
    parts.each_with_index do |part, index|
      raise Error, "The ISO path does not name a directory." unless directory[:directory]
      @directory_bytes += directory[:size]
      raise Error, "The ISO directory scan exceeds its read budget." if @directory_bytes > DIRECTORY_BUDGET
      data = bytes_at(directory[:offset], directory[:size])
      offset = 0
      found = nil
      while offset < data.bytesize
        length = data.getbyte(offset)
        if length.zero?
          offset = (offset / SECTOR_SIZE + 1) * SECTOR_SIZE
          next
        end
        raise Error, "The ISO directory record crosses a sector." if offset % SECTOR_SIZE + length > SECTOR_SIZE
        entry = record(data.byteslice(offset, length))
        if entry[:name].sub(/;.*\z/, "").casecmp?(part)
          found = entry
          break
        end
        offset += length
      end
      raise Error, "The ISO does not contain #{part}." unless found
      directory = found
      raise Error, "The ISO boot file is a directory." if index == parts.size - 1 && directory[:directory]
    end
    directory
  end

  def record(data)
    raise Error, "The ISO directory record is malformed." unless data && data.bytesize >= 34 && data.getbyte(0) == data.bytesize && 33 + data.getbyte(32) <= data.bytesize
    raise Error, "Multi-extent, interleaved, or extended-attribute ISO files are unsupported." unless data.getbyte(1).zero? && (data.getbyte(25) & 0x80).zero? && data.getbyte(26).zero? && data.getbyte(27).zero?
    offset = data.byteslice(2, 4).unpack1("V") * SECTOR_SIZE
    size = data.byteslice(10, 4).unpack1("V")
    raise Error, "The ISO extent is outside the disc." unless offset <= @size && size <= @size - offset
    { offset: offset, size: size, directory: (data.getbyte(25) & 2) != 0, name: data.byteslice(33, data.getbyte(32)) }
  end

  def bytes_at(offset, length)
    raise Error, "The ISO read is outside the disc." unless offset >= 0 && length >= 0 && offset <= @size && length <= @size - offset
    @file.seek(offset)
    bytes = @file.read(length)
    raise Error, "The ISO is truncated." unless bytes && bytes.bytesize == length
    bytes
  end
end

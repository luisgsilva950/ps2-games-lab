require "fileutils"
require "json"
require "open3"
require "pathname"
require "tempfile"

# PCSX2 2.8.2 native per-game layer. Only these four INI entries are owned;
# frame limiting is a boot option (-unlimited), not an INI setting in 2.8.2.
class Pcsx2GameSettings
  class Error < StandardError; end
  SETTINGS = {
    "resolution" => [ "EmuCore/GS", "upscale_multiplier", { "native" => "1", "2x" => "2", "3x" => "3", "4x" => "4", "6x" => "6" } ],
    "renderer" => [ "EmuCore/GS", "Renderer", { "auto" => "-1", "metal" => "17", "vulkan" => "14", "opengl" => "12", "software" => "13" } ],
    "filtering" => [ "EmuCore/GS", "filter", { "automatic" => "2", "nearest" => "0", "bilinear" => "1" } ],
    "audio_sync" => [ "SPU2/Output", "SyncMode", { "timestretch" => "TimeStretch", "none" => "Disabled" } ]
  }.freeze
  FILE_LIMIT = 1024 * 1024

  def self.with_launch_lock(data_root)
    [ data_root.parent.parent, data_root.parent, data_root ].each do |path|
      raise Error, "The managed PCSX2 directory contains an unsafe symbolic link." if File.symlink?(path)
    end
    FileUtils.mkdir_p(data_root, mode: 0o700)
    File.open(data_root.join(".lab-launch.lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
      raise Error, "The PCSX2 launch lock is unsafe." unless lock.stat.file? && lock.stat.nlink == 1
      raise Error, "Another PCSX2 launch is being prepared. Retry after it finishes." unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      ensure_stopped!
      yield
    end
  end

  def self.ensure_stopped!
    # Conservatively refuse any native PCSX2 process. This also covers instances
    # launched outside Rails, for which no PID is recorded. Never signal them.
    output, status = Open3.capture2("ps", "-A", "-o", "comm=")
    raise Error, "PCSX2 sessions could not be checked. Close PCSX2 and retry from a supported desktop session." unless status.success?
    if output.lines.any? { |line| File.basename(line.strip).match?(/\Apcsx2(?:[-.].*)?\z/i) }
      raise Error, "PCSX2 is already running. Close it normally before launching again; its settings and unsaved session were left unchanged."
    end
  end

  def initialize(profile)
    @profile = Pathname.new(profile)
  end

  def apply(image_path, tuning)
    validate_tuning!(tuning)
    begin
      identity = Ps2DiscIdentity.read(image_path)
    rescue Ps2DiscIdentity::Error => error
      return if tuning.empty? # Ordinary untuned launch does not require identification.
      raise Error, "Per-game tuning could not identify this ISO: #{error.message}"
    end
    directory = settings_directory
    reject_directory_links!(directory)
    filename = identity.settings_filename.to_s
    unless filename.match?(/\A(?:[A-Z0-9-]+_)?[0-9A-F]{8}\.ini\z/)
      raise Error, "The disc identity does not name a safe PCSX2 game settings file."
    end
    legacy_filename = format("%08X.ini", Integer(identity.crc))
    path = directory.join(filename)
    legacy = directory.join(legacy_filename)
    if !path.exist? && !File.symlink?(path) && (legacy.exist? || File.symlink?(legacy))
      filename = legacy_filename
      path = legacy
    end
    state_path = directory.join(".lab-tuning-#{filename}.json")
    original = safe_read(path) || "".b
    state_bytes = safe_read(state_path)
    return if tuning.empty? && !state_bytes
    state = state_bytes ? JSON.parse(state_bytes) : {}
    validate_state!(state)
    lines = original.lines
    old_state = state.dup
    SETTINGS.each do |name, (section, key, values)|
      current = entry_lines(lines, section, key)
      if tuning.key?(name)
        state[name] ||= current
        replace_entry!(lines, section, key, [ "#{key} = #{values.fetch(tuning.fetch(name))}\n" ])
      elsif state.key?(name)
        replace_entry!(lines, section, key, state.fetch(name))
      end
    end
    validate_state!(state)
    self.class.ensure_stopped!
    FileUtils.mkdir_p(directory, mode: 0o700)
    # Save restoration data before replacing native settings, so a failed config
    # publication never loses the user's original values.
    atomic_write(state_path, JSON.generate(state)) unless state == old_state
    saved_state = state.dup
    replacement = lines.join
    atomic_write(path, replacement) unless replacement == original
    state.delete_if { |name, _| !tuning.key?(name) }
    if state.empty?
      File.unlink(state_path) if state_path.exist?
    else
      atomic_write(state_path, JSON.generate(state)) unless state == saved_state
    end
    identity
  rescue JSON::ParserError
    raise Error, "The saved native tuning restoration metadata is invalid. No configuration was changed."
  end

  private

  def validate_tuning!(tuning)
    valid = tuning.is_a?(Hash) && tuning.all? do |key, value|
      key == "frame_limit" ? %w[enabled disabled].include?(value) : SETTINGS.key?(key) && SETTINGS.fetch(key)[2].key?(value)
    end
    raise Error, "The saved per-game tuning settings are invalid. Save supported settings before launching." unless valid
  end

  def settings_directory
    base = safe_read(@profile.join("inis", "PCSX2.ini")) || ""
    lines = entry_lines(base.lines, "Folders", "GameSettings")
    value = lines.last&.split("=", 2)&.last&.strip
    value = "gamesettings" if value.nil? || value.empty?
    directory = @profile.join(value).expand_path
    unless directory.to_s.start_with?("#{@profile.expand_path}/") && !value.match?(/[\x00\r\n]/)
      raise Error, "The native GameSettings folder is outside the managed PCSX2 profile. Restore it inside that profile before using lab tuning."
    end
    directory
  end

  def reject_directory_links!(directory)
    path = directory
    loop do
      raise Error, "The per-game settings directory contains an unsafe symbolic link." if File.symlink?(path)
      break if path == @profile || path == path.parent
      path = path.parent
    end
  end

  def safe_read(path)
    return unless path.exist? || File.symlink?(path)
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      stat = file.stat
      raise Error, "The native PCSX2 settings or restoration file is unsafe or too large." unless stat.file? && stat.nlink == 1 && stat.size <= FILE_LIMIT
      file.read
    end
  rescue Errno::ELOOP
    raise Error, "The native PCSX2 settings or restoration file is an unsafe symbolic link."
  end

  def entry_lines(lines, section, key)
    selected = []
    current = nil
    lines.each do |line|
      current = line.strip[1...-1] if line.strip.match?(/\A\[[^\]]+\]\z/)
      selected << line if current == section && line.match?(/\A[ \t]*#{Regexp.escape(key)}[ \t]*=/)
    end
    selected
  end

  def replace_entry!(lines, section, key, replacements)
    current = nil
    indices = []
    section_start = nil
    section_end = lines.length
    lines.each_with_index do |line, index|
      if line.strip.match?(/\A\[[^\]]+\]\z/)
        section_end = index if current == section && section_end == lines.length
        current = line.strip[1...-1]
        section_start ||= index if current == section
      end
      indices << index if current == section && line.match?(/\A[ \t]*#{Regexp.escape(key)}[ \t]*=/)
    end
    insertion = indices.first || section_end
    indices.reverse_each { |index| lines.delete_at(index) }
    return if replacements.empty?
    unless section_start
      lines << "\n" unless lines.empty? || lines.last.end_with?("\n")
      lines << "[#{section}]\n"
      insertion = lines.length
    end
    if insertion.positive? && !lines[insertion - 1].end_with?("\n")
      lines.insert(insertion, "\n")
      insertion += 1
    end
    lines.insert(insertion, *replacements)
  end

  def validate_state!(state)
    valid = state.is_a?(Hash) && state.all? do |name, originals|
      SETTINGS.key?(name) && originals.is_a?(Array) && originals.size <= 32 && originals.all? do |line|
        line.is_a?(String) && line.bytesize <= 4096 && line.match?(/\A[ \t]*#{Regexp.escape(SETTINGS.fetch(name)[1])}[ \t]*=[^\r\n]*(?:\r?\n)?\z/)
      end
    end
    raise Error, "The saved native tuning restoration metadata is invalid. No configuration was changed." unless valid
  end

  def atomic_write(path, bytes)
    safe_read(path) # Recheck symlinks/hardlinks immediately before publication.
    Tempfile.create([ ".lab-tuning-", ".tmp" ], path.dirname) do |file|
      file.binmode
      file.chmod(0o600)
      file.write(bytes)
      file.flush
      file.fsync
      File.rename(file.path, path)
    end
  end
end

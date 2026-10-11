require "digest"
require "fileutils"
require "pathname"

class EmulatorLauncher
  class ConfigurationError < StandardError; end
  class ImageError < StandardError; end

  def launch(game_image)
    game_image.reload
    raise ImageError, "Only a ready imported image can be launched." unless game_image.ready?

    executable = executable_path
    bios = bios_file
    data_root = prepare_configuration(bios)
    image_path = verified_image_path(game_image)

    # PCSX2 Qt CLI: https://pcsx2.net/docs/advanced/cli
    # -bios boots the system menu; it does NOT select a BIOS file.
    pid = Process.spawn([ executable, executable ], "-datapath", data_root.to_s, "-batch", "--", image_path.to_s,
      in: File::NULL, out: File::NULL, err: File::NULL)
    Process.detach(pid)
    game_image.update!(launch_status: "launched", launch_error: nil)
    :launched
  rescue ConfigurationError => error
    game_image.update!(launch_status: "not_configured", launch_error: error.message)
    :not_configured
  rescue ImageError => error
    game_image.update!(launch_status: "failed", launch_error: error.message)
    :failed
  rescue StandardError
    game_image.update!(launch_status: "failed", launch_error: "PCSX2 could not be started. Check executable permissions, BIOS configuration, and the desktop session.")
    :failed
  end

  private

  def executable_path
    path = ENV["PCSX2_EXECUTABLE"].to_s
    unless absolute_path?(path) && File.file?(path) && File.executable?(path)
      raise ConfigurationError, "Set PCSX2_EXECUTABLE to the absolute path of the installed PCSX2 executable (not the .app directory)."
    end
    File.realpath(path)
  end

  def bios_file
    path = ENV["PCSX2_BIOS_PATH"].to_s
    unless absolute_path?(path)
      raise ConfigurationError, "Set PCSX2_BIOS_PATH to an absolute readable BIOS file or a directory containing a BIOS .bin or .rom file."
    end

    if File.directory?(path)
      path = Dir.children(path).sort.filter_map do |name|
        candidate = File.join(path, name)
        candidate if %w[.bin .rom].include?(File.extname(name).downcase) && readable_file?(candidate)
      end.first
    end
    unless path && readable_file?(path)
      raise ConfigurationError, "PCSX2_BIOS_PATH does not contain a readable nonempty BIOS file. Supply a BIOS dumped from your own console."
    end
    resolved = File.realpath(path)
    unless absolute_path?(resolved) && File.basename(resolved) == File.basename(resolved).strip
      raise ConfigurationError, "The BIOS filename cannot contain line breaks or surrounding whitespace."
    end
    resolved
  end

  def absolute_path?(path)
    path.present? && Pathname.new(path).absolute? && !path.match?(/[\x00\r\n]/) && path == path.strip
  end

  def readable_file?(path)
    File.file?(path) && File.readable?(path) && File.size(path).positive?
  end

  def prepare_configuration(bios)
    # Isolate saves and configuration from the user's normal PCSX2 installation.
    # These keys are read by PCSX2 Qt's Pcsx2Config.cpp and QtHost.cpp.
    data_root = Rails.root.join("storage", "pcsx2", Digest::SHA256.hexdigest(bios))
    settings = data_root.join("inis")
    [ Rails.root.join("storage"), data_root.parent, data_root, settings ].each do |directory|
      raise ConfigurationError, "The managed PCSX2 configuration directory contains an unsafe symbolic link." if File.symlink?(directory)
    end
    FileUtils.mkdir_p(settings, mode: 0o700)
    config_path = settings.join("PCSX2.ini")
    begin
      File.open(config_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write("[UI]\nSettingsVersion = 1\nSetupWizardIncomplete = false\n\n[Folders]\nBios = #{File.dirname(bios)}\n\n[Filenames]\nBIOS = #{File.basename(bios)}\n")
      end
    rescue Errno::EEXIST
      stat = File.lstat(config_path)
      unless stat.file? && stat.nlink == 1
        raise ConfigurationError, "The managed PCSX2 settings file is unsafe."
      end
    end
    data_root
  end

  def verified_image_path(game_image)
    path = game_image.managed_path
    unless File.realpath(path) == File.expand_path(path)
      raise ImageError, "The imported image path contains a symbolic link. Launch was refused."
    end
    game_image.verify_original!
  rescue ImageError
    raise
  rescue StandardError
    raise ImageError, "The managed original is missing, unsafe, or its recorded size/SHA-256 has changed. Launch was refused."
  end
end

class OsxCpuTemp < Formula
  desc "Outputs current CPU temperature for OSX"
  homepage "https://github.com/lavoiesl/osx-cpu-temp"
  url "https://github.com/lavoiesl/osx-cpu-temp/archive/refs/tags/1.1.0.tar.gz"
  sha256 "94b90ce9a1c7a428855453408708a5557bfdb76fa45eef2b8ded4686a1558363"
  license "GPL-2.0-or-later"

  # The Catalina bottle tab has built_on: null (pre-2.5 Homebrew artifact), which
  # causes modern Homebrew to crash in Utils::Bottles.load_tab when it calls
  # tab.built_on["os"] without a nil guard. Build from source to avoid this.
  pour_bottle? do
    false
  end

  depends_on :macos

  def install
    system "make"
    bin.install "osx-cpu-temp"
  end

  test do
    assert_match "°C", shell_output("#{bin}/osx-cpu-temp -C")
  end
end

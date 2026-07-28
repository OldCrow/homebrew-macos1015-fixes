class Tesseract < Formula
  desc "OCR (Optical Character Recognition) engine"
  homepage "https://tesseract-ocr.github.io/"
  url "https://github.com/tesseract-ocr/tesseract/archive/refs/tags/5.5.3.tar.gz"
  sha256 "9218e62793116d42a9f6d14cd9348518b27f382096eea3d0f2d1a24616bb5884"
  license "Apache-2.0"
  compatibility_version 1
  head "https://github.com/tesseract-ocr/tesseract.git", branch: "main"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "pkgconf" => :build
  depends_on "cairo"
  depends_on "fontconfig"
  depends_on "glib"
  depends_on "harfbuzz"
  depends_on "icu4c@78"
  depends_on "leptonica"
  depends_on "libarchive"
  depends_on "pango"

  on_macos do
    depends_on "freetype"
    depends_on "gettext"
  end

  resource "eng" do
    url "https://github.com/tesseract-ocr/tessdata_fast/raw/4.1.0/eng.traineddata"
    sha256 "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2"
  end

  resource "osd" do
    url "https://github.com/tesseract-ocr/tessdata_fast/raw/4.1.0/osd.traineddata"
    sha256 "9cf5d576fcc47564f11265841e5ca839001e7e6f38ff7f7aacf46d15a96b00ff"
  end

  resource "snum" do
    url "https://github.com/USCDataScience/counterfeit-electronics-tesseract/raw/319a6eeacff181dad5c02f3e7a3aff804eaadeca/Training%20Tesseract/snum.traineddata"
    sha256 "36f772980ff17c66a767f584a0d80bf2302a1afa585c01a226c1863afcea1392"
  end

  def install
    # Problem: six hard errors in src/ccstruct/points.h, e.g.
    #   error: constexpr function never produces a constant expression
    #          [-Winvalid-constexpr]
    #   constexpr inline FCOORD operator!(...)
    #   note: non-constexpr constructor 'FCOORD' cannot be used in a constant
    #         expression
    #
    # Root cause: these operators default-construct an FCOORD and then assign
    # to its members. FCOORD's `= default` constructor leaves both float
    # members uninitialized, so the body can only ever be a constant
    # expression from C++20 onward (P1331R2, trivial default initialization in
    # constexpr contexts). Under C++17 Clang rejects it via
    # -Winvalid-constexpr, which is an error by default.
    #
    # This is NOT an Apple Clang 12 code-generation bug: Homebrew LLVM 22
    # rejects the same code at -std=c++17, so the usual ENV.llvm_clang
    # workaround does not help. Other platforms never see it because
    # configure.ac probes `-std=c++17` then `-std=c++20` and lands on C++20.
    # Apple Clang 12 (Xcode 12 / macOS 10.15) predates the `c++20` spelling
    # and accepts only `-std=c++2a`, so the second probe fails and configure
    # silently falls back to C++17 -- exposing the latent bug.
    #
    # Fix: have the probe ask for `-std=c++2a` so Apple Clang 12 is also
    # configured in C++20 mode, matching every other platform. `-std=c++2a`
    # stays a valid alias on newer compilers, so this is version-agnostic.
    # Must run before autogen.sh, which regenerates configure from
    # configure.ac.
    #
    # Remove this formula once tesseract's C++17 path is made conforming
    # upstream (initialize FCOORD's members, or drop constexpr from those
    # operators), or once homebrew-core ships a Catalina bottle.
    inreplace "configure.ac",
              "AX_CHECK_COMPILE_FLAG([-std=c++20], [CPLUSPLUS=20]",
              "AX_CHECK_COMPILE_FLAG([-std=c++2a], [CPLUSPLUS=2a]"

    # explicitly state leptonica header location, as the makefile defaults to /usr/local/include,
    # which doesn't work for non-default homebrew location
    ENV["LIBLEPT_HEADERSDIR"] = HOMEBREW_PREFIX/"include"

    ENV.cxx11

    system "./autogen.sh"
    system "./configure", "--datarootdir=#{HOMEBREW_PREFIX}/share",
                          "--disable-silent-rules",
                          *std_configure_args

    system "make", "training"

    # make install in the local share folder to avoid permission errors
    system "make", "install", "training-install", "datarootdir=#{share}"

    resource("snum").stage { mv "snum.traineddata", share/"tessdata" }
    resource("eng").stage { mv "eng.traineddata", share/"tessdata" }
    resource("osd").stage { mv "osd.traineddata", share/"tessdata" }
  end

  def caveats
    <<~EOS
      This formula contains only the "eng", "osd", and "snum" language data files.
      If you need any other supported languages, run `brew install tesseract-lang`.
    EOS
  end

  test do
    resource "homebrew-test_resource" do
      url "https://raw.githubusercontent.com/tesseract-ocr/test/6dd816cdaf3e76153271daf773e562e24c928bf5/testing/eurotext.tif"
      sha256 "7b9bd14aba7d5e30df686fbb6f71782a97f48f81b32dc201a1b75afe6de747d6"
    end

    resource("homebrew-test_resource").stage do
      system bin/"tesseract", "./eurotext.tif", "./output", "-l", "eng"
      assert_match "The (quick) [brown] {fox} jumps!\n", File.read("output.txt")
    end
  end
end

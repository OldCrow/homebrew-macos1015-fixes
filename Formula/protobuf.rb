class Protobuf < Formula
  desc "Protocol buffers (Google's data interchange format)"
  homepage "https://protobuf.dev/"
  url "https://github.com/protocolbuffers/protobuf/releases/download/v34.0/protobuf-34.0.tar.gz"
  sha256 "e540aae70d3b4f758846588768c9e39090fab880bc3233a1f42a8ab8d3781efd"
  license "BSD-3-Clause"
  compatibility_version 1

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on "cmake" => :build
  depends_on "abseil"

  on_macos do
    # Apple Clang 12.x (macOS 10.15/Xcode 12) misparses [[gnu::warn_unused]] on
    # class declarations. PROTOBUF_FUTURE_ADD_EARLY_WARN_UNUSED expands via
    # ABSL_ATTRIBUTE_WARN_UNUSED to [[gnu::warn_unused]], which combined with
    # __attribute__((visibility(...))) causes the compiler to treat GzipInputStream
    # and GzipOutputStream as anonymous classes, cascading to 20 build failures
    # in gzip_stream.cc. Use Homebrew LLVM to avoid this.
    depends_on "googletest" => :build
    depends_on "llvm" => :build
  end

  on_linux do
    depends_on "llvm" => :build if DevelopmentTools.gcc_version < 13
    depends_on "zlib-ng-compat"
  end

  fails_with :gcc do
    version "12"
    cause "fails handling ABSL_ATTRIBUTE_WARN_UNUSED"
  end

  def install
    ENV.llvm_clang if OS.mac?
    ENV.llvm_clang if OS.linux? && deps.map(&:name).any?("llvm")

    # Keep `CMAKE_CXX_STANDARD` in sync with the same variable in `abseil.rb`.
    abseil_cxx_standard = 17
    cmake_args = %W[
      -DCMAKE_CXX_STANDARD=#{abseil_cxx_standard}
      -DBUILD_SHARED_LIBS=ON
      -Dprotobuf_BUILD_LIBPROTOC=ON
      -Dprotobuf_BUILD_SHARED_LIBS=ON
      -Dprotobuf_INSTALL_EXAMPLES=ON
      -Dprotobuf_BUILD_TESTS=#{OS.mac? ? "ON" : "OFF"}
      -Dprotobuf_FORCE_FETCH_DEPENDENCIES=OFF
      -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON
    ]

    system "cmake", "-S", ".", "-B", "build", *cmake_args, *std_cmake_args
    system "cmake", "--build", "build"
    system "ctest", "--test-dir", "build", "--verbose"
    system "cmake", "--install", "build"

    (share/"vim/vimfiles/syntax").install "editors/proto.vim"
    elisp.install "editors/protobuf-mode.el"
  end

  test do
    (testpath/"test.proto").write <<~PROTO
      syntax = "proto3";
      package test;
      message TestCase {
        string name = 4;
      }
      message Test {
        repeated TestCase case = 1;
      }
    PROTO
    system bin/"protoc", "test.proto", "--cpp_out=."
  end
end

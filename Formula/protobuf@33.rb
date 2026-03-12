class ProtobufAT33 < Formula
  desc "Protocol buffers (Google's data interchange format)"
  homepage "https://protobuf.dev/"
  url "https://github.com/protocolbuffers/protobuf/releases/download/v33.5/protobuf-33.5.tar.gz"
  sha256 "c6c7c27fadc19d40ab2eaa23ff35debfe01f6494a8345559b9bb285ce4144dd1"
  license "BSD-3-Clause"

  livecheck do
    url :stable
    regex(/^v?(33(?:\.\d+)+)$/i)
  end

  keg_only :versioned_formula

  # Support for protoc 33.x (protobuf C++ 6.33.x) will end on 2027-03-31
  # Ref: https://protobuf.dev/support/version-support/#cpp
  deprecate! date: "2027-03-31", because: :versioned_formula

  depends_on "cmake" => :build
  depends_on "abseil"

  on_macos do
    # Use Homebrew LLVM for ABI consistency with wolfman/macos1015-fixes/abseil,
    # which is compiled with LLVM. Tests disabled: absl::Cord template instantiation
    # is missing from the LLVM abseil dylib when test code is Apple-Clang-compiled
    # (mangling mismatch between compilers for complex enable_if NTTPs).
    depends_on "llvm" => :build
  end

  on_linux do
    depends_on "zlib-ng-compat"
  end

  def install
    ENV.llvm_clang if OS.mac?

    # Keep `CMAKE_CXX_STANDARD` in sync with the same variable in `abseil.rb`.
    abseil_cxx_standard = 17
    cmake_args = %W[
      -DCMAKE_CXX_STANDARD=#{abseil_cxx_standard}
      -DBUILD_SHARED_LIBS=ON
      -Dprotobuf_BUILD_LIBPROTOC=ON
      -Dprotobuf_BUILD_SHARED_LIBS=ON
      -Dprotobuf_INSTALL_EXAMPLES=ON
      -Dprotobuf_BUILD_TESTS=OFF
      -Dprotobuf_FORCE_FETCH_DEPENDENCIES=OFF
      -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON
    ]

    system "cmake", "-S", ".", "-B", "build", *cmake_args, *std_cmake_args
    system "cmake", "--build", "build"
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

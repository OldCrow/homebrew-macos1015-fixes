class Grpc < Formula
  desc "Next generation open source RPC library and framework"
  homepage "https://grpc.io/"
  url "https://github.com/grpc/grpc.git",
      tag:      "v1.78.1",
      revision: "5b6492ea90b2b867a6adad1b10a6edda28e860d1"
  license "Apache-2.0"
  revision 2
  compatibility_version 1
  head "https://github.com/grpc/grpc.git", branch: "master"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
    strategy :github_releases
  end

  bottle do
    rebuild 1
    sha256 cellar: :any, arm64_tahoe:   "aec56e6c00c9e2731b076fa474af1c72d38f930a31b42beafc7c605f3900f97c"
    sha256 cellar: :any, arm64_sequoia: "aa6173766eadbec001d8668f241b9f538a0288b874f8f367d9d5c13b58cdcfbe"
    sha256 cellar: :any, arm64_sonoma:  "05fff1a84df10fdf2aad256c09812dd2aee481ff4c1872a03533dcdc035ee735"
    sha256 cellar: :any, sonoma:        "f83adaee52b346e32500691541cab06c8b798d67d9f33ceb26c6600028257b49"
    sha256               arm64_linux:   "e8cb24e7983383547590a5bfd28b1e5e756c81bfc9041669f13f9a0b60f4cdd5"
    sha256               x86_64_linux:  "2a0b0a024984e29d57386574b10009e6f6e3b452d32fad6687983fe37b4bdb4f"
  end

  depends_on "cmake" => :build
  depends_on "pkgconf" => :test
  depends_on "abseil"
  depends_on "c-ares"
  depends_on "openssl@3"
  depends_on "protobuf"
  depends_on "re2"

  on_macos do
    # Apple Clang 12.x (macOS 10.15/Xcode 12) produces a different C++ name
    # mangling for enable_if non-type template parameters than LLVM 22.
    # absl::Cord::Cord<string, 0> and similar symbols in our LLVM-compiled
    # abseil use LLVM's Tn-encoded NTTP ABI; Apple Clang code looks for the
    # older Li0E-encoded form and gets an undefined symbol at link time.
    # Using LLVM for grpc ensures it uses the same ABI as our abseil build.
    depends_on "llvm" => :build
  end

  on_linux do
    depends_on "zlib-ng-compat"
  end

  fails_with :clang do
    build 1100
    cause "Requires C++17 features not yet implemented"
  end

  # Apply open PR to support building grpc_cli with Protobuf 34+
  # PR ref: https://github.com/grpc/grpc/pull/41775
  patch do
    url "https://github.com/grpc/grpc/commit/168b069208538e58a72bf46a6410f9ac0d24019a.patch?full_index=1"
    sha256 "406731204b925c3ba57c8dc84da573b2755c3365cd59c1f0a04c1791f7db6565"
  end

  def install
    ENV.llvm_clang if OS.mac?

    args = %W[
      -DCMAKE_CXX_STANDARD=17
      -DCMAKE_INSTALL_RPATH=#{rpath}
      -DBUILD_SHARED_LIBS=ON
      -DgRPC_INSTALL=ON
      -DgRPC_ABSL_PROVIDER=package
      -DgRPC_CARES_PROVIDER=package
      -DgRPC_PROTOBUF_PROVIDER=package
      -DgRPC_SSL_PROVIDER=package
      -DgRPC_ZLIB_PROVIDER=package
      -DgRPC_RE2_PROVIDER=package
    ]
    system "cmake", "-S", ".", "-B", "_build", "-DgRPC_BUILD_TESTS=OFF", *args, *std_cmake_args
    system "cmake", "--build", "_build"
    system "cmake", "--install", "_build"

    # grpc_cli: upstream is dropping it at 1.80.0 and the benchmark dependency
    # fails to configure with LLVM on macOS 10.15, so skip it here.
  end

  test do
    ENV.llvm_clang if OS.mac?

    (testpath/"test.cpp").write <<~CPP
      #include <grpc/grpc.h>
      int main() {
        grpc_init();
        grpc_shutdown();
        return GRPC_STATUS_OK;
      }
    CPP

    ENV.prepend_path "PKG_CONFIG_PATH", Formula["openssl@3"].opt_lib/"pkgconfig"
    ENV.prepend_path "PKG_CONFIG_PATH", Formula["zlib-ng-compat"].opt_lib/"pkgconfig" if OS.linux?
    flags = shell_output("pkgconf --cflags --libs libcares protobuf re2 grpc++").chomp.split
    system ENV.cc, "test.cpp", "-L#{Formula["abseil"].opt_lib}", *flags, "-o", "test"
    system "./test"
  end
end

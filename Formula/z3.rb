class Z3 < Formula
  desc "High-performance theorem prover"
  homepage "https://github.com/Z3Prover/z3"
  url "https://github.com/Z3Prover/z3/archive/refs/tags/z3-4.16.0.tar.gz"
  sha256 "c68c3e5e4810b16126b8cb4c47eee85c1ac3e24a81914c8e371b40de9dd33ac7"
  license "MIT"
  head "https://github.com/Z3Prover/z3.git", branch: "master"

  depends_on "cmake" => :build
  depends_on "python@3.14" => [:build, :test]

  def python3
    which("python3.14")
  end

  def install
    # z3 4.16.0 uses std::format (C++20), which requires libc++ from macOS 14+.
    # Apple Clang 12 / macOS 10.15 compiles C++20 syntax but ships an older libc++
    # that lacks <format>. Inject a minimal polyfill header that implements
    # std::format using ostringstream. z3 only uses plain {} positional specifiers.
    # Note: llvm depends on z3, so we cannot use llvm as a build dependency here.
    compat_dir = buildpath/"format-compat"
    compat_dir.mkpath
    (compat_dir/"format").write <<~CPP
      #pragma once
      // std::format polyfill for macOS 10.15 / Apple Clang 12.
      // Supports only positional {} placeholders (no format-spec), which covers
      // all uses of std::format in z3 4.16.0 src/ast/*.cpp.
      #include <string>
      #include <sstream>
      #include <vector>
      namespace std {
        namespace _z3_fmt_detail {
          template<typename T>
          inline std::string _to_s(const T& v) {
            std::ostringstream o; o << v; return o.str();
          }
          inline std::string _apply(const char* fmt, std::vector<std::string> a) {
            std::string r;
            for (size_t ai = 0; *fmt; ++fmt) {
              if (fmt[0] == '{' && fmt[1] == '}') {
                if (ai < a.size()) r += a[ai++];
                ++fmt;
              } else {
                r += *fmt;
              }
            }
            return r;
          }
        }
        template<typename... A>
        inline std::string format(const char* fmt, A&&... a) {
          return _z3_fmt_detail::_apply(
            fmt, {_z3_fmt_detail::_to_s(std::forward<A>(a))...});
        }
        template<typename... A>
        inline std::string format(const std::string& fmt, A&&... a) {
          return format(fmt.c_str(), std::forward<A>(a)...);
        }
      }
    CPP

    # C++20 parenthesized aggregate initialization (P0960) is absent from Apple
    # Clang 12. Replace key_data(...) with key_data{...} (C++17 brace aggregate
    # initialization), which is semantically identical for this aggregate struct.
    inreplace "src/util/obj_hashtable.h" do |s|
      s.gsub! "key_data(k, v)",            "key_data{k, v}"
      s.gsub! "key_data(k, std::move(v))", "key_data{k, std::move(v)}"
      s.gsub! "key_data(k)",               "key_data{k}"
    end
    # expr2var.cpp uses key_value (a typedef of obj_map::key_data) with ()
    inreplace "src/ast/expr2var.cpp",
      "key_value(n, v)", "key_value{n, v}"

    args = %W[
      -DZ3_LINK_TIME_OPTIMIZATION=ON
      -DZ3_INCLUDE_GIT_DESCRIBE=OFF
      -DZ3_INCLUDE_GIT_HASH=OFF
      -DZ3_INSTALL_PYTHON_BINDINGS=ON
      -DZ3_BUILD_EXECUTABLE=ON
      -DZ3_BUILD_TEST_EXECUTABLES=OFF
      -DZ3_BUILD_PYTHON_BINDINGS=ON
      -DZ3_BUILD_DOTNET_BINDINGS=OFF
      -DZ3_BUILD_JAVA_BINDINGS=OFF
      -DZ3_USE_LIB_GMP=OFF
      -DPYTHON_EXECUTABLE=#{python3}
      -DCMAKE_INSTALL_PYTHON_PKG_DIR=#{Language::Python.site_packages(python3)}
    ]
    args << "-DCMAKE_CXX_FLAGS=-I#{compat_dir}"

    system "cmake", "-S", ".", "-B", "build", *args, *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    system "make", "-C", "contrib/qprofdiff"
    bin.install "contrib/qprofdiff/qprofdiff"

    pkgshare.install "examples"
  end

  test do
    system ENV.cc, pkgshare/"examples/c/test_capi.c", "-I#{include}",
                   "-L#{lib}", "-lz3", "-o", testpath/"test"
    system "./test"
    assert_equal version.to_s, shell_output("#{python3} -c 'import z3; print(z3.get_version_string())'").strip
  end
end

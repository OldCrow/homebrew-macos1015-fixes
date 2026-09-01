class Boost < Formula
  desc "Collection of portable C++ source libraries"
  homepage "https://www.boost.org/"
  url "https://github.com/boostorg/boost/releases/download/boost-1.90.0/boost-1.90.0-b2-nodocs.tar.xz"
  sha256 "9e6bee9ab529fb2b0733049692d57d10a72202af085e553539a05b4204211a6f"
  license "BSL-1.0"
  revision 1
  head "https://github.com/boostorg/boost.git", branch: "master"

  livecheck do
    url "https://www.boost.org/users/download/"
    regex(/href=.*?boost[._-]v?(\d+(?:[._]\d+)+)\.t/i)
    strategy :page_match do |page, regex|
      page.scan(regex).map { |match| match.first.tr("_", ".") }
    end
  end

  depends_on "icu4c@78"
  depends_on "llvm"
  depends_on "xz"
  depends_on "zstd"

  uses_from_macos "bzip2"

  on_linux do
    depends_on "zlib-ng-compat"
  end

  # Fix for `ncmpcpp`, pr ref: https://github.com/boostorg/range/pull/157
  patch :p3 do
    url "https://github.com/boostorg/range/commit/9ac89e9936b826c13e90611cb9a81a7aa0508d20.patch?full_index=1"
    sha256 "914464ffa1d53b3bf56ee0ff1a78c25799170c99c9a1cda075e6298f730236ad"
    directory "boost"
  end

  def install
    # Use Homebrew LLVM on macOS to get proper C++17 support
    # Apple's libc++ on macOS 10.15 lacks std::aligned_alloc required by Boost.Asio
    llvm = Formula["llvm"]
    ENV["CC"] = "#{llvm.opt_bin}/clang"
    ENV["CXX"] = "#{llvm.opt_bin}/clang++"
    ENV["LDFLAGS"] = "-L#{llvm.opt_lib}/c++ -Wl,-rpath,#{llvm.opt_lib}/c++"
    ENV["CPPFLAGS"] = "-I#{llvm.opt_include}"

    # Force boost to compile with the desired compiler.
    #
    # Boost.Build's own internal feature-detection Jamfile checks (which
    # decide whether Boost.IOStreams gets zstd/lzma support) run compiler
    # invocations using ONLY the bare toolset declaration -- they do NOT
    # pick up the `cxxflags=`/`linkflags=` properties passed to the final
    # `b2 install` command further down, and (since CC/CXX point directly
    # at llvm's binary rather than through Homebrew's superenv shim) they
    # don't get the shim's automatic -isystem injection for
    # /usr/local/include (clang does not search it by default on macOS) or
    # its per-dependency -I/-L injection for zstd/xz either. Without any
    # <compileflags>/<linkflags> on the toolset declaration, those checks
    # silently fail to find <zstd.h>/<lzma.h> and libzstd/liblzma, so b2
    # quietly builds Boost.IOStreams without zstd/lzma support -- surfacing
    # later as an undefined-symbol *link* error in any code that calls
    # zstd_compressor()/zstd_decompressor() (or the lzma equivalents), not
    # as a build failure. Embed zstd's and xz's include/lib paths directly
    # in the toolset declaration so every compile Boost.Build performs,
    # including its own internal checks, can find them.
    zstd = Formula["zstd"]
    xz = Formula["xz"]
    compileflags = "-I#{zstd.opt_include} -I#{xz.opt_include}"
    linkflags = "-L#{zstd.opt_lib} -L#{xz.opt_lib}"
    open("user-config.jam", "a") do |file|
      if OS.mac?
        file.write "using darwin : : #{ENV.cxx} : <compileflags>\"#{compileflags}\" <linkflags>\"#{linkflags}\" ;\n"
      else
        file.write "using gcc : : #{ENV.cxx} : <compileflags>\"#{compileflags}\" <linkflags>\"#{linkflags}\" ;\n"
      end
    end

    # libdir should be set by --prefix but isn't
    icu4c = deps.map(&:to_formula).find { |f| f.name.match?(/^icu4c@\d+$/) }
    bootstrap_args = %W[
      --prefix=#{prefix}
      --libdir=#{lib}
      --with-icu=#{icu4c.opt_prefix}
    ]

    # Handle libraries that will not be built.
    without_libraries = ["python", "mpi"]

    # Boost.Log cannot be built using Apple GCC at the moment. Disabled
    # on such systems.
    without_libraries << "log" if ENV.compiler == :gcc

    bootstrap_args << "--without-libraries=#{without_libraries.join(",")}"

    # layout should be synchronized with boost-python and boost-mpi
    args = %W[
      --prefix=#{prefix}
      --libdir=#{lib}
      -d2
      -j#{ENV.make_jobs}
      --layout=system
      --user-config=user-config.jam
      install
      threading=multi
      link=shared,static
    ]

    # Boost is using "clang++ -x c" to select C compiler which breaks C++
    # handling in superenv. Using "cxxflags" and "linkflags" still works.
    # C++17 is due to `icu4c`.
    args << "cxxflags=-std=c++17"
    if ENV.compiler == :clang
      args << "cxxflags=-stdlib=libc++"
      args << "linkflags=-stdlib=libc++ -L#{llvm.opt_lib}/c++ -Wl,-rpath,#{llvm.opt_lib}/c++"
    end

    system "./bootstrap.sh", *bootstrap_args
    system "./b2", "headers"
    system "./b2", *args
  end

  test do
    (testpath/"test.cpp").write <<~CPP
      #include <boost/algorithm/string.hpp>
      #include <boost/iostreams/device/array.hpp>
      #include <boost/iostreams/device/back_inserter.hpp>
      #include <boost/iostreams/filter/zstd.hpp>
      #include <boost/iostreams/filtering_stream.hpp>
      #include <boost/iostreams/stream.hpp>

      #include <string>
      #include <iostream>
      #include <vector>
      #include <assert.h>

      using namespace boost::algorithm;
      using namespace boost::iostreams;
      using namespace std;

      int main()
      {
        string str("a,b");
        vector<string> strVec;
        split(strVec, str, is_any_of(","));
        assert(strVec.size()==2);
        assert(strVec[0]=="a");
        assert(strVec[1]=="b");

        // Test boost::iostreams::zstd_compressor() linking
        std::vector<char> v;
        back_insert_device<std::vector<char>> snk{v};
        filtering_ostream os;
        os.push(zstd_compressor());
        os.push(snk);
        os << "Boost" << std::flush;
        os.pop();

        array_source src{v.data(), v.size()};
        filtering_istream is;
        is.push(zstd_decompressor());
        is.push(src);
        std::string s;
        is >> s;

        assert(s == "Boost");

        return 0;
      }
    CPP
    llvm = Formula["llvm"]
    system "#{llvm.opt_bin}/clang++", "test.cpp", "-std=c++17", "-stdlib=libc++",
                    "-o", "test", "-L#{lib}", "-lboost_iostreams",
                    "-L#{formula_opt_lib("zstd")}", "-lzstd",
                    "-L#{llvm.opt_lib}/c++", "-Wl,-rpath,#{llvm.opt_lib}/c++"
    system "./test"
  end
end

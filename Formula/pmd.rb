class Pmd < Formula
  desc "Source code analyzer for Java, JavaScript, and more"
  homepage "https://pmd.github.io"
  url "https://github.com/pmd/pmd/releases/download/pmd_releases%2F7.24.0/pmd-dist-7.24.0-bin.zip"
  sha256 "110934b36d39c19094d1b77386931978093f238f2c2f1851748822b69c7367ac"
  license "BSD-4-Clause"

  livecheck do
    url :stable
    strategy :github_latest
  end

  # Upstream depends_on "openjdk" (currently JDK 25) but PMD 7.x only requires
  # Java 8+. openjdk@21 is the highest LTS that builds on macOS 10.15.
  depends_on "wolfman/macos1015-fixes/openjdk@21"

  def install
    rm Dir["bin/*.bat"]
    libexec.install Dir["*"]
    (bin/"pmd").write_env_script libexec/"bin/pmd", Language::Java.overridable_java_home_env
  end

  test do
    (testpath/"java/testClass.java").write <<~JAVA
      public class BrewTestClass {
        // dummy constant
        public String SOME_CONST = "foo";

        public boolean doTest () {
          return true;
        }
      }
    JAVA

    output = shell_output("#{bin}/pmd check -d #{testpath}/java " \
                          "-R category/java/bestpractices.xml -f json")
    assert_empty JSON.parse(output)["processingErrors"]
  end
end

require 'formula'

class HadoopSnappy < Formula
  homepage 'https://code.google.com/p/hadoop-snappy/'
  url 'http://hadoop-snappy.googlecode.com/svn/trunk/', :using => :svn
  version 'head'  # the latest known good svn revision is 38, there are no known bad reversions.

  depends_on :autoconf
  depends_on :automake
  depends_on :libtool
  depends_on 'snappy'

  def install
    snappy_prefix = Dir["#{prefix}/../../snappy/*"].last
    ohai "Using snappy prefix #{snappy_prefix}"
    system "mvn package -Dsnappy.prefix=#{snappy_prefix}"

    lib.install Dir['target/native-build/usr/local/lib/*']
    prefix.install Dir['target/hadoop-snappy-0.0.1-SNAPSHOT.jar']
    libexec.install Dir['*']
  end
end

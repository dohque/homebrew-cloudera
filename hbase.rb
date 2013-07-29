require 'formula'

class Hbase < Formula
  version '0.94.6-cdh4.3.0'
  homepage 'http://www.cloudera.com/content/cloudera/en/products/cdh.html'
  url 'http://archive.cloudera.com/cdh4/cdh/4/hbase-0.94.6-cdh4.3.0.tar.gz'
  sha1 'bffa0e5ebca596e8511a8cbb141de29b7654a246'

  option 'with-snappy', 'Include support for the snappy codec'
  snappy_dep = build.with?('snappy') ? 'with-snappy' : 'without-snappy'

  depends_on 'seomoz/cloudera/hadoop' => snappy_dep

  def patches
    DATA
  end

  def install
    hbase_home.install Dir['*']

    # This conflicts with the same jar in the hadoop classpath, which is always present.
    (hbase_home/'lib'/'slf4j-log4j12-1.6.1.jar').delete

    # These are similar, but merely overlap. Ordering is important, so we want to respect
    # the ordering in the hadoop classpath. However, by removing these we are now required
    # to have 'hadoop' available on the daemon PATHs, to make their classpaths complete.
    (hbase_home/'lib'/'hadoop-annotations-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-auth-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-common-2.0.0-cdh4.3.0-tests.jar').delete
    (hbase_home/'lib'/'hadoop-common-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-hdfs-2.0.0-cdh4.3.0-tests.jar').delete
    (hbase_home/'lib'/'hadoop-hdfs-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-mapreduce-client-app-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-mapreduce-client-common-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-mapreduce-client-core-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-mapreduce-client-hs-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-mapreduce-client-jobclient-2.0.0-cdh4.3.0-tests.jar').delete
    (hbase_home/'lib'/'hadoop-mapreduce-client-jobclient-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-mapreduce-client-shuffle-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-api-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-client-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-common-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-server-common-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-server-nodemanager-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-server-resourcemanager-2.0.0-cdh4.3.0.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-server-tests-2.0.0-cdh4.3.0-tests.jar').delete
    (hbase_home/'lib'/'hadoop-yarn-server-web-proxy-2.0.0-cdh4.3.0.jar').delete

    # Here's a place for native libraries
    native_lib_dir = hbase_home/'lib'/'native'/'Mac_OS_X-x86_64-64'
    FileUtils.mkdir_p native_lib_dir
    FileUtils.touch native_lib_dir/'.keep'

    # Wire in the snappy codec if requested, by using hadoop-snappy's drop-in SnappyCodec
    # replacement.  This depends directly on libsnappy instead of libhadoop, allowing it to
    # work on OSX.
    if build.with?('snappy')
      jar_path = Dir["#{prefix}/../../hadoop-snappy/*/hadoop-snappy-*.jar"].last
      (hbase_home/'lib').install_symlink jar_path

      # The underscore forces it to appear early in hbase' classpath
      jar_name = File.basename(jar_path)
      FileUtils.mv "#{hbase_home}/lib/#{jar_name}", "#{hbase_home}/lib/_hadoop-snappy.jar"

      native_lib_dir.install_symlink Dir["#{HOMEBREW_PREFIX}/lib/libsnappy.*"]
      native_lib_dir.install_symlink Dir["#{HOMEBREW_PREFIX}/lib/libhadoopsnappy.*"]
    end

    bin.write_exec_script "#{hbase_home}/bin/hbase"
    bin.write_exec_script "#{hbase_home}/bin/start-hbase.sh"
    bin.write_exec_script "#{hbase_home}/bin/stop-hbase.sh"

    hbase_plist 'master'
    hbase_plist 'regionserver'
    hbase_plist 'zookeeper'
  end

  def caveats; <<-EOS.undent
    #{hbase_home}/lib/slf4j-log4j12-1.6.1.jar has been removed,
      since it duplicates the same jar in hadoop, which SLF4J warns about.

    In #{hbase_home}/conf/hbase-env.sh:
        $JAVA_HOME has been set to be the output of /usr/libexec/java_home
        "-Djava.security.krb5.realm= -Djava.security.krb.kdc=" has been added to
        $HBASE_OPTS. See http://stackoverflow.com/q/7134723/580412

    In #{hbase_home}/conf/hbase-site.xml:
        hbase.zookeeper.quorum has been set to localhost
        hbase.rootdir has been set to hdfs://localhost:8020/hbase
        hbase.cluster.distributed has been set to true
        dfs.support.append has been set to true
        dfs.client.read.shortcircuit has been set to true

    In #{hbase_home}/conf/log4j.properties:
        The level of util.NativeCodeLoader has been set to error.

    In #{hbase_home}/lib:
        Several jars common to hadoop have been removed, allowing hadoop to
        specify their appearance order in the CLASSPATH.  They are:
        hadoop-annotations-2.0.0-cdh4.3.0.jar
        hadoop-auth-2.0.0-cdh4.3.0.jar
        hadoop-common-2.0.0-cdh4.3.0-tests.jar
        hadoop-common-2.0.0-cdh4.3.0.jar
        hadoop-hdfs-2.0.0-cdh4.3.0-tests.jar
        hadoop-hdfs-2.0.0-cdh4.3.0.jar
        hadoop-mapreduce-client-app-2.0.0-cdh4.3.0.jar
        hadoop-mapreduce-client-common-2.0.0-cdh4.3.0.jar
        hadoop-mapreduce-client-core-2.0.0-cdh4.3.0.jar
        hadoop-mapreduce-client-hs-2.0.0-cdh4.3.0.jar
        hadoop-mapreduce-client-jobclient-2.0.0-cdh4.3.0-tests.jar
        hadoop-mapreduce-client-jobclient-2.0.0-cdh4.3.0.jar
        hadoop-mapreduce-client-shuffle-2.0.0-cdh4.3.0.jar
        hadoop-yarn-api-2.0.0-cdh4.3.0.jar
        hadoop-yarn-client-2.0.0-cdh4.3.0.jar
        hadoop-yarn-common-2.0.0-cdh4.3.0.jar
        hadoop-yarn-server-common-2.0.0-cdh4.3.0.jar
        hadoop-yarn-server-nodemanager-2.0.0-cdh4.3.0.jar
        hadoop-yarn-server-resourcemanager-2.0.0-cdh4.3.0.jar
        hadoop-yarn-server-tests-2.0.0-cdh4.3.0-tests.jar
        hadoop-yarn-server-web-proxy-2.0.0-cdh4.3.0.jar

    To have launchd start #{name} at login:
        mkdir -p ~/Library/LaunchAgents
        ln -sfv #{HOMEBREW_PREFIX}/opt/#{name}/*.plist ~/Library/LaunchAgents
    Then to load #{name} now:
        launchctl load ~/Library/LaunchAgents/homebrew.mxcl.hbase-*.plist
    Or, if you don't want/need launchctl, you can just run:
        start-hbase.sh
    EOS
  end

private

  def hbase_home
    libexec
  end

  # We have multiple, similar services.  This writes instances of a launchd plist template.
  def hbase_plist(name)
    plist_file = plist_path.dirname/"homebrew.mxcl.hbase-#{name}.plist"
    plist_file.write <<-EOS.undent
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
        <dict>
          <key>KeepAlive</key>
          <true/>
          <key>Label</key>
          <string>homebrew.mxcl.hbase-#{name}</string>
          <key>ProgramArguments</key>
          <array>
            <string>#{hbase_home}/bin/hbase</string>
            <string>--config</string>
            <string>#{hbase_home}/conf</string>
            <string>#{name}</string>
            <string>start</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>WorkingDirectory</key>
          <string>#{hbase_home}</string>
          <key>EnvironmentVariables</key>
          <dict>
            <!-- We must ensure the hadoop binary is visible on PATH -->
            <!-- Otherwise hadoop jars will fail to appear on the daemon classpaths -->
            <key>PATH</key>
            <string>/usr/bin:/bin:/usr/sbin:/sbin:#{HOMEBREW_PREFIX}/bin</string>
          </dict>
        </dict>
      </plist>
    EOS
    plist_file.chmod 0644
  end
end

__END__
diff --git a/conf/hbase-env.sh b/conf/hbase-env.sh
index 86f388b..ca0654d 100644
--- a/conf/hbase-env.sh
+++ b/conf/hbase-env.sh
@@ -26,7 +26,7 @@
 # into the startup scripts (bin/hbase, etc.)

 # The java implementation to use.  Java 1.6 required.
-# export JAVA_HOME=/usr/java/jdk1.6.0/
+export JAVA_HOME="$(/usr/libexec/java_home)"

 # Extra Java CLASSPATH elements.  Optional.
 # export HBASE_CLASSPATH=
@@ -38,7 +38,7 @@
 # Below are what we set by default.  May only work with SUN JVM.
 # For more on why as well as other possible settings,
 # see http://wiki.apache.org/hadoop/PerformanceTuning
-export HBASE_OPTS="-XX:+UseConcMarkSweepGC"
+export HBASE_OPTS="-XX:+UseConcMarkSweepGC -Djava.security.krb5.realm= -Djava.security.krb.kdc="

 # Uncomment below to enable java garbage collection logging for the server-side processes
 # this enables basic gc logging for the server processes to the .out file
diff --git a/conf/hbase-site.xml b/conf/hbase-site.xml
index af4c300..f35a20b 100644
--- a/conf/hbase-site.xml
+++ b/conf/hbase-site.xml
@@ -22,4 +22,24 @@
  */
 -->
 <configuration>
+  <property>
+    <name>hbase.zookeeper.quorum</name>
+    <value>localhost</value>
+  </property>
+  <property>
+    <name>hbase.rootdir</name>
+    <value>hdfs://localhost:8020/hbase</value>
+  </property>
+  <property>
+    <name>hbase.cluster.distributed</name>
+    <value>true</value>
+  </property>
+  <property>
+    <name>dfs.support.append</name>
+    <value>true</value>
+  </property>
+  <property>
+    <name>dfs.client.read.shortcircuit</name>
+    <value>true</value>
+  </property>
 </configuration>
diff --git a/conf/log4j.properties b/conf/log4j.properties
index 2f3bb51..a3aa99f 100644
--- a/conf/log4j.properties
+++ b/conf/log4j.properties
@@ -87,3 +87,6 @@ log4j.logger.org.apache.hadoop.hbase.zookeeper.ZooKeeperWatcher=INFO
 # and scan of .META. messages
 # log4j.logger.org.apache.hadoop.hbase.client.HConnectionManager$HConnectionImplementation=INFO
 # log4j.logger.org.apache.hadoop.hbase.client.MetaScanner=INFO
+
+# Disable native code loader warnings.
+log4j.logger.org.apache.hadoop.util.NativeCodeLoader=error

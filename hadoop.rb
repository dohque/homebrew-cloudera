require 'formula'
require 'keg'

class Keg
  def plist_installed?
    # Annoyingly, homebrew checks for *.plist but assumes a fixed name.
    # This determines if the standard plist caveats are displayed.
    # By tightening the check, we suppress them.
    (self/"homebrew.mxcl.#{parent.basename}.plist").exist?
  end
end

class Hadoop < Formula
  version '2.0.0-cdh4.5.0'
  homepage 'http://www.cloudera.com/content/cloudera/en/products/cdh.html'
  url 'http://archive.cloudera.com/cdh4/cdh/4/hadoop-2.0.0-cdh4.5.0.tar.gz'
  sha1 '17e73e63d666daf9cbe803e4f92d9494dd11217d'

  module MR1; end
  module MR2; end

  # Both are packaged, but cannot coexist.  MR2 is considered unstable at time of writing.
  # See http://www.cloudera.com/content/cloudera-content/cloudera-docs/CDH4/latest/
  # under 'CDH4 Installation Guide' ->
  #       'Deploying CDH4 on a Cluster' ->
  #       'Deploying MapReduce v2 (YARN) on a Cluster'
  #
  # See also http://stackoverflow.com/a/15628377/580412
  option 'with-mr2', 'Install MR2 and YARN instead of MR1'
  include build.with?('mr2') ? MR2 : MR1

  option 'with-snappy', 'Include support for the snappy codec'
  depends_on 'seomoz/cloudera/hadoop-snappy' if build.with?('snappy')

  module MR1
    def patches
      DATA
    end

    def install
      abort_hooks = []

      hadoop_home.install Dir['*']

      # These assume they are sibling to tools in bin.
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/distribute-exclude.sh"
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/refresh-namenodes.sh"
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/start-balancer.sh"
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/start-dfs.sh"
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/start-secure-dns.sh"
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/stop-balancer.sh"
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/stop-dfs.sh"
      (hadoop_home/'bin').install_symlink "#{hadoop_home}/sbin/stop-secure-dns.sh"

      # Don't make rcc visible, it conflicts with Qt
      bin.write_exec_script "#{hadoop_home}/bin-mapreduce1/hadoop"
      bin.write_exec_script "#{hadoop_home}/bin-mapreduce1/start-mapred.sh"
      bin.write_exec_script "#{hadoop_home}/bin-mapreduce1/stop-mapred.sh"
      bin.write_exec_script "#{hadoop_home}/bin/hdfs"
      bin.write_exec_script "#{hadoop_home}/bin/distribute-exclude.sh"
      bin.write_exec_script "#{hadoop_home}/bin/refresh-namenodes.sh"
      bin.write_exec_script "#{hadoop_home}/bin/start-balancer.sh"
      bin.write_exec_script "#{hadoop_home}/bin/start-dfs.sh"
      bin.write_exec_script "#{hadoop_home}/bin/start-secure-dns.sh"
      bin.write_exec_script "#{hadoop_home}/bin/stop-balancer.sh"
      bin.write_exec_script "#{hadoop_home}/bin/stop-dfs.sh"
      bin.write_exec_script "#{hadoop_home}/bin/stop-secure-dns.sh"

      # Grab all the pseudo-distributed config files.
      # Skip hadoop-metrics.properties as it appears to merely be stale.
      (hadoop_home/'conf').mkdir
      (hadoop_home/'conf').install_symlink Dir["#{hadoop_home}/etc/hadoop-mapreduce1-pseudo/*.xml"]

      # Grab everything from vanilla MR1 that wasn't covered by the pseudo-distributed stuff
      # Except the log4j.properties; that one is old, we'll use the one in etc/hadoop/
      (hadoop_home/'conf').install_symlink(Dir["#{hadoop_home}/etc/hadoop-mapreduce1/*"] - [
        "#{hadoop_home}/etc/hadoop-mapreduce1/core-site.xml",
        "#{hadoop_home}/etc/hadoop-mapreduce1/hdfs-site.xml",
        "#{hadoop_home}/etc/hadoop-mapreduce1/log4j.properties",
        "#{hadoop_home}/etc/hadoop-mapreduce1/mapred-site.xml"
      ])

      # Grab log4j.properties from etc/hadoop/
      (hadoop_home/'conf').install_symlink "#{hadoop_home}/etc/hadoop/log4j.properties"

      # This must be here for start-mapred.sh (actually bin-mapreduce1/hadoop-config.sh)
      hadoop_home.install_symlink \
        "#{hadoop_home}/share/hadoop/mapreduce1/hadoop-core-2.0.0-mr1-cdh4.3.0.jar"

      # bin-mapreduce1/hadoop expects to find webapps in the HADOOP_HOME
      hadoop_home.install_symlink "#{hadoop_home}/share/hadoop/mapreduce1/webapps"

      # Create a place for long-lived (hdfs) data.
      FileUtils.mkdir_p hadoop_var/'dfs-name'
      FileUtils.mkdir_p hadoop_var/'dfs-data'
      FileUtils.mkdir_p hadoop_var/'mapred-local'

      check_ssh_localhost
      check_hostname_dns_reverse_lookup

      # Here's a place for jars that must appear early ("first") in the hadoop classpath
      early_classpath_dir = hadoop_home/'lib'/'first'
      FileUtils.mkdir_p early_classpath_dir
      FileUtils.touch early_classpath_dir/'.keep'

      # Here's a place for native libraries
      native_lib_dir = hadoop_home/'lib'/'native'/'Mac_OS_X-x86_64-64'
      FileUtils.mkdir_p native_lib_dir
      FileUtils.touch native_lib_dir/'.keep'

      # Wire in the snappy codec if requested, by using hadoop-snappy's drop-in SnappyCodec
      # replacement.  This depends directly on libsnappy instead of libhadoop, allowing it to
      # work on OSX.
      if build.with?('snappy')
        the_jar = Dir["#{prefix}/../../hadoop-snappy/*/hadoop-snappy-*.jar"].last
        early_classpath_dir.install_symlink the_jar

        native_lib_dir.install_symlink Dir["#{HOMEBREW_PREFIX}/lib/libsnappy.*"]
        native_lib_dir.install_symlink Dir["#{HOMEBREW_PREFIX}/lib/libhadoopsnappy.*"]
      end

      # Format the name node & create some standard directory structure if fresh
      if fresh_install?
        system "#{hadoop_home}/bin/hdfs namenode -format"
        abort_hooks << lambda { hadoop_var.rmtree }

        system "#{hadoop_home}/bin/start-dfs.sh"
        abort_hooks << lambda { system "#{hadoop_home}/bin/stop-dfs.sh" }

        system "#{hadoop_home}/bin/hdfs dfs -mkdir /tmp"
        system "#{hadoop_home}/bin/hdfs dfs -chmod 1777 /tmp"
        system "#{hadoop_home}/bin/hdfs dfs -mkdir /mapred"
        system "#{hadoop_home}/bin/hdfs dfs -mkdir /mapred/system"
        system "#{hadoop_home}/bin/hdfs dfs -mkdir /user"
        system "#{hadoop_home}/bin/hdfs dfs -mkdir /user/$USER"

        system "#{hadoop_home}/bin/stop-dfs.sh"
      end

      hadoop_plist 'namenode', 'bin/hdfs'
      hadoop_plist 'datanode', 'bin/hdfs'
      hadoop_plist 'secondarynamenode', 'bin/hdfs'
      hadoop_plist 'jobtracker', 'bin-mapreduce1/hadoop'
      hadoop_plist 'tasktracker', 'bin-mapreduce1/hadoop'
    rescue
      onoe "Aborting..."
      abort_hooks.reverse.map(&:call)
      raise
    end

    def caveats; <<-EOS.undent
      Using pseudo-distrbuted config files, installed in #{hadoop_home}/conf

      In #{hadoop_home}/conf/hadoop-env.sh:
          $JAVA_HOME has been set to be the output of /usr/libexec/java_home
          #{hadoop_home}/lib/first/* has been added early in the hadoop classpath
          $HADOOP_COMMON_LIB_NATIVE_DIR has been set to "lib/native/Mac_OS_X-x86_64-64"
          "-Djava.security.krb5.realm= -Djava.security.krb.kdc=" has been added to
          $HADOOP_OPTS and $HADOOP_CLIENT_OPTS. See http://stackoverflow.com/q/7134723/580412

      In #{hadoop_home}/conf/core-site.xml:
          fs.default.name (deprecated) has been dropped in favor of fs.defaultFS
          hadoop.tmp.dir has been set to /tmp/hdfs-${user.name}.

      In #{hadoop_home}/conf/hdfs-site.xml:
          dfs.name.dir has been set to #{hadoop_var}/dfs-name
          dfs.data.dir has been set to #{hadoop_var}/dfs-data

      In #{hadoop_home}/conf/mapred-site.xml:
          mapred.local.dir has been set to #{hadoop_var}/mapred-local

      In #{hadoop_home}/bin-mapreduce1/hadoop-daemon.sh:
          "$HADOOP_HOME"/bin/hadoop has been changed to "$HADOOP_HOME"/bin-mapreduce1/hadoop.
          This allows start-mapred.sh to function.

      In #{hadoop_home}/etc/hadoop/log4j.properties:
          The level of util.NativeCodeLoader has been set to error.

      You need to be able to ssh to localhost as yourself using a public key.
          If you didn't see a warning above about it, you're good.
          See http://borrelli.org/2012/05/02/hadoop-osx-sshkey_setup/

      Your effective FQDN (as given by hostname -f) should resolve to a local IP.
          If you didn't see a warning above about it, you're probably good.
          See http://stackoverflow.com/q/4730148/580412

      If this was a fresh install, we also
          'hadoop namenode -format' to initialize the name node
          Created basic directory structure in HDFS

      If you wanted a fresh install and didn't get one, delete #{hadoop_var} and try again.
      Beware you will lose all data in HDFS if you do!

      To have launchd start #{name} at login:
          mkdir -p ~/Library/LaunchAgents
          ln -sfv #{HOMEBREW_PREFIX}/opt/#{name}/*.plist ~/Library/LaunchAgents
      Then to load #{name} now:
          launchctl load ~/Library/LaunchAgents/homebrew.mxcl.hadoop-*.plist
      Or, if you don't want/need launchctl, you can just run:
          start-dfs.sh && start-mapred.sh
      EOS
    end
  end

  module MR2
    def install
      onoe "MR2 support is not yet implemented!  Pull requests are welcome."
      exit 1

      # libexec.install Dir['*']

      # bin.write_exec_script Dir["#{libexec}/bin/*"]
      # bin.write_exec_script Dir["#{libexec}/sbin/*"]
      # (bin/'Linux-amd64-64').unlink # Hide linux-native stuff

      # # Don't make rcc visible, it conflicts with Qt
      # (bin/'rcc').unlink
    end
  end

private

  def hadoop_home
    libexec
  end

  # Where hadoop keeps data that should persist across upgrades
  def hadoop_var
    var/'hadoop'
  end

  def fresh_install?
    @fresh_install ||= Dir["#{hadoop_var}/dfs-name/*"].empty?.tap do |fresh|
      if fresh
        ohai "This seems to be a fresh install"
      else
        ohai "This does not seem to be a fresh install (#{hadoop_var}/dfs-name is not empty)"
      end
    end
  end

  # Can we SSH to ourselves?
  def check_ssh_localhost
    # BatchMode=yes prevents password authentication
    # Interestingly PasswordAuthentication=no does not seem to disable it.
    unless 'success' == %x{ssh -o BatchMode=yes localhost echo success}.chomp
      abort "You need to allow key-based SSH access to localhost for your own user.\n" +
            "See http://borrelli.org/2012/05/02/hadoop-osx-sshkey_setup/"
    end
  end

  # Does our fqdn (as given by hostname -f) resolve to ourselves?
  def check_hostname_dns_reverse_lookup
    my_fqdn = %x{hostname -f}.chomp
    if !$?.success?
      opoo "You can't run 'hostname -f'!? I can't check your hostname dns reverse lookup."
    elsif %x{traceroute -m 2 "#{my_fqdn}" 2>/dev/null}.chomp.lines.to_a.size != 1 || !$?.success?
      # Actually, passing this check only proves that the name is bound to someone in your subnet.
      opoo "Your effective FQDN (#{my_fqdn}) doesn't seem to traceroute to yourself."
    end
  end

  # We have multiple, similar services.  This writes instances of a launchd plist template.
  def hadoop_plist(name, launcher)
    plist_file = plist_path.dirname/"homebrew.mxcl.hadoop-#{name}.plist"
    plist_file.write <<-EOS.undent
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
        <dict>
          <key>KeepAlive</key>
          <true/>
          <key>Label</key>
          <string>homebrew.mxcl.hadoop-#{name}</string>
          <key>ProgramArguments</key>
          <array>
            <string>#{hadoop_home}/#{launcher}</string>
            <string>--config</string>
            <string>#{hadoop_home}/conf</string>
            <string>#{name}</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>WorkingDirectory</key>
          <string>#{hadoop_home}</string>
          <key>StandardErrorPath</key>
          <string>#{hadoop_home}/logs/#{name}.err</string>
          <key>StandardOutPath</key>
          <string>#{hadoop_home}/logs/#{name}.out</string>
        </dict>
      </plist>
    EOS
    plist_file.chmod 0644
  end
end

__END__
diff --git a/bin-mapreduce1/hadoop-daemon.sh b/bin-mapreduce1/hadoop-daemon.sh
index d502099..87d5009 100755
--- a/bin-mapreduce1/hadoop-daemon.sh
+++ b/bin-mapreduce1/hadoop-daemon.sh
@@ -117,7 +117,7 @@ case $startStop in
     echo starting $command, logging to $_HADOOP_DAEMON_OUT
     cd "$HADOOP_HOME"

-    nice -n $HADOOP_NICENESS "$HADOOP_HOME"/bin/hadoop --config $HADOOP_CONF_DIR $command "$@" < /dev/null
+    nice -n $HADOOP_NICENESS "$HADOOP_HOME"/bin-mapreduce1/hadoop --config $HADOOP_CONF_DIR $command "$@" < /dev/null
     ;;

   (stop)
diff --git a/etc/hadoop-mapreduce1-pseudo/core-site.xml b/etc/hadoop-mapreduce1-pseudo/core-site.xml
index 3878ff1..9aafdb3 100644
--- a/etc/hadoop-mapreduce1-pseudo/core-site.xml
+++ b/etc/hadoop-mapreduce1-pseudo/core-site.xml
@@ -3,13 +3,13 @@

 <configuration>
   <property>
-    <name>fs.default.name</name>
+    <name>fs.defaultFS</name>
     <value>hdfs://localhost:8020</value>
   </property>

   <property>
      <name>hadoop.tmp.dir</name>
-     <value>/var/lib/hadoop-0.20/cache/${user.name}</value>
+     <value>/tmp/hdfs-${user.name}</value>
   </property>

   <!-- OOZIE proxy user setting -->
diff --git a/etc/hadoop-mapreduce1-pseudo/hdfs-site.xml b/etc/hadoop-mapreduce1-pseudo/hdfs-site.xml
index 991ed52..4e19d6a 100644
--- a/etc/hadoop-mapreduce1-pseudo/hdfs-site.xml
+++ b/etc/hadoop-mapreduce1-pseudo/hdfs-site.xml
@@ -23,24 +23,10 @@
   <property>
      <!-- specify this so that running 'hadoop namenode -format' formats the right dir -->
      <name>dfs.name.dir</name>
-     <value>/var/lib/hadoop-0.20/cache/hadoop/dfs/name</value>
-  </property>
-
-  <!-- Enable Hue Plugins -->
-  <property>
-    <name>dfs.namenode.plugins</name>
-    <value>org.apache.hadoop.thriftfs.NamenodePlugin</value>
-    <description>Comma-separated list of namenode plug-ins to be activated.
-    </description>
-  </property>
-  <property>
-    <name>dfs.datanode.plugins</name>
-    <value>org.apache.hadoop.thriftfs.DatanodePlugin</value>
-    <description>Comma-separated list of datanode plug-ins to be activated.
-    </description>
+     <value>HOMEBREW_PREFIX/var/hadoop/dfs-name</value>
   </property>
   <property>
-    <name>dfs.thrift.address</name>
-    <value>0.0.0.0:10090</value>
+    <name>dfs.data.dir</name>
+    <value>HOMEBREW_PREFIX/var/hadoop/dfs-data</value>
   </property>
 </configuration>
diff --git a/etc/hadoop-mapreduce1-pseudo/mapred-site.xml b/etc/hadoop-mapreduce1-pseudo/mapred-site.xml
index 5535a6d..8d9e83a 100644
--- a/etc/hadoop-mapreduce1-pseudo/mapred-site.xml
+++ b/etc/hadoop-mapreduce1-pseudo/mapred-site.xml
@@ -6,16 +6,8 @@
     <name>mapred.job.tracker</name>
     <value>localhost:8021</value>
   </property>
-
-  <!-- Enable Hue plugins -->
-  <property>
-    <name>mapred.jobtracker.plugins</name>
-    <value>org.apache.hadoop.thriftfs.ThriftJobTrackerPlugin</value>
-    <description>Comma-separated list of jobtracker plug-ins to be activated.
-    </description>
-  </property>
   <property>
-    <name>jobtracker.thrift.address</name>
-    <value>0.0.0.0:9290</value>
+    <name>mapred.local.dir</name>
+    <value>HOMEBREW_PREFIX/var/hadoop/mapred-local</value>
   </property>
 </configuration>
diff --git a/etc/hadoop-mapreduce1/hadoop-env.sh b/etc/hadoop-mapreduce1/hadoop-env.sh
index ce7ccc8..a12cca5 100644
--- a/etc/hadoop-mapreduce1/hadoop-env.sh
+++ b/etc/hadoop-mapreduce1/hadoop-env.sh
@@ -6,16 +6,20 @@
 # remote nodes.

 # The java implementation to use.  Required.
-# export JAVA_HOME=/usr/lib/j2sdk1.6-sun
+export JAVA_HOME="$(/usr/libexec/java_home)"

 # Extra Java CLASSPATH elements.  Optional.
 # export HADOOP_CLASSPATH="<extra_entries>:$HADOOP_CLASSPATH"
+export HADOOP_CLASSPATH="$HADOOP_CONF_DIR/../lib/first/*:$HADOOP_CLASSPATH"
+export HADOOP_USER_CLASSPATH_FIRST="true"
+export HADOOP_COMMON_LIB_NATIVE_DIR="lib/native/Mac_OS_X-x86_64-64"

 # The maximum amount of heap to use, in MB. Default is 1000.
 # export HADOOP_HEAPSIZE=2000

 # Extra Java runtime options.  Empty by default.
 # if [ "$HADOOP_OPTS" == "" ]; then export HADOOP_OPTS=-server; else HADOOP_OPTS+=" -server"; fi
+export HADOOP_OPTS="$HADOOP_OPTS -Djava.security.krb5.realm= -Djava.security.krb.kdc="

 # Command specific options appended to HADOOP_OPTS when specified
 export HADOOP_NAMENODE_OPTS="-Dcom.sun.management.jmxremote $HADOOP_NAMENODE_OPTS"
@@ -26,6 +29,7 @@ export HADOOP_JOBTRACKER_OPTS="-Dcom.sun.management.jmxremote $HADOOP_JOBTRACKER
 # export HADOOP_TASKTRACKER_OPTS=
 # The following applies to multiple commands (fs, dfs, fsck, distcp etc)
 # export HADOOP_CLIENT_OPTS
+export HADOOP_CLIENT_OPTS="$HADOOP_CLIENT_OPTS -Djava.security.krb5.realm= -Djava.security.krb.kdc="

 # Extra ssh options.  Empty by default.
 # export HADOOP_SSH_OPTS="-o ConnectTimeout=1 -o SendEnv=HADOOP_CONF_DIR"
diff --git a/etc/hadoop/log4j.properties b/etc/hadoop/log4j.properties
index b92ad27..bd29256 100644
--- a/etc/hadoop/log4j.properties
+++ b/etc/hadoop/log4j.properties
@@ -217,3 +217,6 @@ log4j.additivity.org.apache.hadoop.mapred.JobInProgress$JobSummary=false
 #log4j.appender.RMSUMMARY.MaxBackupIndex=20
 #log4j.appender.RMSUMMARY.layout=org.apache.log4j.PatternLayout
 #log4j.appender.RMSUMMARY.layout.ConversionPattern=%d{ISO8601} %p %c{2}: %m%n
+
+# Disable native code loader warnings.
+log4j.logger.org.apache.hadoop.util.NativeCodeLoader=error

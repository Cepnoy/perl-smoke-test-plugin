require 'open-uri'
require 'simple/console'

class PerlSmokeTestBuilder < Jenkins::Tasks::Builder

    attr_accessor :enabled, :distro_url, :redirect_url
    attr_accessor :paths
    attr_accessor :ssh_host, :ssh_login
    attr_accessor :verbose_output, :catalyst_debug, :color_output

    display_name "Run Smoke Tests on Perl Application" 

    # Invoked with the form parameters when this extension point
    # is created from a configuration screen.
    def initialize(attrs = {})
        @attrs = attrs
        @enabled = attrs["enabled"]
        @distro_url = attrs["distro_url"]
        @redirect_url = attrs["redirect_url"]
        @paths = attrs["paths"] || ""
        @ssh_host = attrs["ssh_host"]
        @ssh_login = attrs["ssh_login"]
        @verbose_output = attrs["verbose_output"]
        @catalyst_debug = attrs["catalyst_debug"]
        @color_output = attrs['color_output']
    end

    ##
    # Runs before the build begins
    #
    # @param [Jenkins::Model::Build] build the build which will begin
    # @param [Jenkins::Model::Listener] listener the listener for this build.
    def prebuild(build, listener)
      # do any setup that needs to be done before this build runs.
    end
    ##
    # Runs the step over the given build and reports the progress to the listener.
    #
    # @param [Jenkins::Model::Build] build on which to run this step
    # @param [Jenkins::Launcher] launcher the launcher that can run code on the node running this build
    # @param [Jenkins::Model::Listener] listener the listener for this build.
    def perform(build, launcher, listener)

      # actually perform the build step
        sc  = Simple::Console.new(:color_output => @color_output)
        env = build.native.getEnvironment()
        job = build.send(:native).get_project.name


        # start smoke tests
        if @enabled == true 

            if @redirect_url == true
                listener.info sc.info(@distro_url, :title => 'redirect url')
                distro_url = URI.parse(@distro_url).read.chomp
            else
                distro_url = @distro_url
            end

            dist_name = distro_url.split('/').last
            dist_dir = dist_name.sub('.tar.gz','')

            listener.info sc.info(distro_url, :title => 'distro_url')
            listener.info sc.info(dist_name, :title => 'dist_name')
            listener.info sc.info(dist_dir, :title => 'dist_dir')

            if ( env['LC_ALL'].nil? || env['LC_ALL'].empty? )
                ssh_cmd = "ssh #{@ssh_login}@#{@ssh_host}"
            else
                ssh_cmd = "export LC_ALL=#{env['LC_ALL']} && ssh #{@ssh_login}@#{@ssh_host}"
            end

            curl_verbosity = @verbose_output == true ? '--verbose' : '-s'

            listener.info sc.info('upload distributive to host',:title => 'stage')
            listener.info sc.info(@ssh_host, :title => 'ssh host')

            cmd = []
            cmd << "rm -rf .perl_smoke_test/"
            cmd << "mkdir .perl_smoke_test/"
            cmd << "cd .perl_smoke_test/"
            cmd << "curl -L -f #{distro_url} -o #{dist_name} #{curl_verbosity}"
            build.abort unless launcher.execute("bash", "-c", "#{ssh_cmd} '#{cmd.join(' && ')}'", { :out => listener } ) == 0

            listener.info sc.info('unpack distributive',:title => 'stage')
            cmd = []
            cmd << "cd .perl_smoke_test/"
            cmd << "tar -xzf #{dist_name}"
            cmd << "cd #{dist_dir}"
            build.abort unless launcher.execute("bash", "-c", "#{ssh_cmd} '#{cmd.join(' && ')}'", { :out => listener } ) == 0


            listener.info sc.info("check prerequisitives",:title => 'stage')
            cmd = []
            cmd << "cd .perl_smoke_test/"
            cmd << "cd #{dist_dir}"
            if ( env['PERL5LIB'].nil? || env['PERL5LIB'].empty? )
                cmd << "export PERL5LIB=./cpanlib/lib/perl5" 
            else
                cmd << "export PERL5LIB=./cpanlib/lib/perl5:#{env['PERL5LIB']}" 
            end
            cmd << "if test -e Build.PL; then perl Build.PL && ./Build && ./Build prereq_report > report.txt && cat report.txt && if grep '\\!' report.txt; then exit 1; fi; fi"
            build.abort unless launcher.execute("bash", "-c", "#{ssh_cmd} '#{cmd.join(' && ')}'", { :out => listener } ) == 0


            listener.info sc.info("run application tests",:title => 'stage')
            test_verbose = ''
            catalyst_debug = '0'
            test_verbose = @verbose_output == true ? '--verbose=1' : ''
            makemaker_verbose = @verbose_output == true ? 'TEST_VERBOSE=1' : ''
            catalyst_debug = '1' if @catalyst_debug == true

            cmd = []
            cmd << "cd .perl_smoke_test/"
            cmd << "cd #{dist_dir}"
            if ( env['PERL5LIB'].nil? || env['PERL5LIB'].empty? )
                cmd << "export PERL5LIB=./cpanlib/lib/perl5" 
            else
                cmd << "export PERL5LIB=./cpanlib/lib/perl5:#{env['PERL5LIB']}" 
            end            
            cmd << "if test -e Build.PL; then ./Build && CATALYST_DEBUG=#{catalyst_debug} ./Build test #{test_verbose} && if [ `echo $?` -ne 0 ]; then exit 1;fi; fi"
            cmd << "if test -e Makefile.PL; then perl Makefile.PL && make && make test && if [ `echo $?` -ne 0 ]; then exit 1;fi; fi"

            build.abort unless launcher.execute("bash", "-c", "#{ssh_cmd} '#{cmd.join(' && ')}'", { :out => listener } ) == 0


            # check paths
            listener.info sc.info("check perl scripts",:title => 'stage')
            @paths.split("\n").map {|l| l.chomp }.reject {|l| l.nil? || l.empty? || l =~ /^\s+#/ || l =~ /^#/ }.map{ |l| l.sub(/#.*/){""} }.each do |l|
                cmd = []
                cmd << "cd .perl_smoke_test/"
                cmd << "cd #{dist_dir}"
                if ( env['PERL5LIB'].nil? || env['PERL5LIB'].empty? )
                    cmd << "export PERL5LIB=./cpanlib/lib/perl5" 
                else
                    cmd << "export PERL5LIB=./cpanlib/lib/perl5:#{env['PERL5LIB']}" 
                end
                cmd << "perl -c #{l}"
                listener.info sc.info(l,:title => 'check')
                build.abort unless launcher.execute("bash", "-c", "#{ssh_cmd} '#{cmd.join(' && ')}'", { :out => listener } ) == 0
            end  


        end # if @enabled == true

    end

end

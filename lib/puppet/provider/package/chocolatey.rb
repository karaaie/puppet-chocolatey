# authored by Rich Siegel (rismoney@gmail.com)
# with help from some of the other pkg providers of course

require 'puppet/provider/package'

Puppet::Type.type(:package).provide(:chocolatey, :parent => Puppet::Provider::Package) do
  desc "Package management using Chocolatey on Windows"
  confine    :operatingsystem => :windows

  has_feature :installable, :uninstallable, :upgradeable, :versionable, :install_options


  def powershell(args)
    args = args.join(' ')

    #Powershell
    #  http://msdn.microsoft.com/en-us/library/windows/desktop/aa384187%28v=vs.85%29.aspx
    #  For 32-bit processes on 64-bit systems, %windir%\system32 folder
    #  can only be accessed by specifying %windir%\sysnative folder.
    #
    #  Puppet Agent process currently always runs in 32 bit mode, so the following powershell seems appropriate
    powershell_exe = native_path("#{ENV['SYSTEMROOT']}\\sysnative\\WindowsPowershell\\v1.0\\powershell.exe")
    powershell_args = " -NoProfile -NonInteractive -NoLogo -ExecutionPolicy unrestricted" 
    powershell = " \"#{powershell_exe}\" #{powershell_args}" 

    #Chocolatey
    chocopath = native_path("#{ENV['ChocolateyInstall'] || 'C:\\Chocolatey' }\\chocolateyInstall\\chocolatey.ps1")
    choco_command = " -Command #{chocopath} #{args}"
    
    #Execute the command
    system "cmd.exe /c  \"#{powershell} #{choco_command}\" \""
  end

  def native_path(path)
    path.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
  end

  def self.chocolatey_command
    chocopath = ENV['ChocolateyInstall'] || 'C:\Chocolatey'
    chocopath + "\\chocolateyInstall\\chocolatey.cmd"
  end

  #Is this required ?
  commands :chocolatey => chocolatey_command

 def print()
   notice("The value is: '${name}'")
 end

  # This command potentially triggers chocolateyInstall.ps1
  # Which in turn might depend on 64 bit modules (Such as IIS WebAdministration)
  # Thus we're piping it di
  def install
    should = @resource.should(:ensure)
    case should
    when true, false, Symbol
      args = "install", @resource[:name][/\A\S*/], resource[:install_options]
    else
      # Add the package version
      args = "install", @resource[:name][/\A\S*/], "-version", resource[:ensure], resource[:install_options]
    end

    if @resource[:source]
      args << "-source" << resource[:source]
    end

    powershell(args)
  end

  def uninstall
    args = "uninstall", @resource[:name][/\A\S*/]
    powershell(args)
  end

  def update
    args = "update", @resource[:name][/\A\S*/], resource[:install_options]

    if @resource[:source]
      args << "-source" << resource[:source]
    end

    powershell(args)
  end

  # from puppet-dev mailing list
  # Puppet will call the query method on the instance of the package
  # provider resource when checking if the package is installed already or
  # not.
  # It's a determination for one specific package, the package modeled by
  # the resource the method is called on.
  # Query provides the information for the single package identified by @Resource[:name].

  def query
    self.class.instances.each do |provider_chocolatey|
      return provider_chocolatey.properties if @resource[:name][/\A\S*/] == provider_chocolatey.name
    end
    return nil
  end

  def self.listcmd
    powershell("list -lo")
  end

  def self.instances
    packages = []

    begin
      execpipe(listcmd()) do |process|
        process.each_line do |line|
          line.chomp!
          if line.empty? or line.match(/Reading environment variables.*/); next; end
          values = line.split(' ')
          packages << new({ :name => values[0], :ensure => values[1], :provider => self.name })
        end
      end
    rescue Puppet::ExecutionFailure
      return nil
    end
    packages
  end

  def latestcmd
    powershell(" version #{@resource[:name][/\A\S*/]} | findstr /R 'latest' | findstr /V 'latestCompare' ")
    #[command(:chocolatey), ' version ' + @resource[:name][/\A\S*/] + ' | findstr /R "latest" | findstr /V "latestCompare" ']
  end

  def latest
    packages = []

    begin
      output = execpipe(latestcmd()) do |process|

        process.each_line do |line|
          line.chomp!
          if line.empty?; next; end
          # Example: ( latest        : 2013.08.19.155043 )
          values = line.split(':').collect(&:strip).delete_if(&:empty?)
          return values[1]
        end
      end
    rescue Puppet::ExecutionFailure
      return nil
    end
    packages
  end

end

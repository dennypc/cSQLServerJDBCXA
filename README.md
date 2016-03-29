#cSQLServerJDBCXA

PowerShell CmdLets and Class-Based DSC resources to enable JDBC XA Transactions on SQL Server

To get started using this module just type the command below and the module will be downloaded from [PowerShell Gallery](https://www.powershellgallery.com/packages/cSQLServerJDBCXA/)
```shell
PS> Install-Module -Name cSQLServerJDBCXA
```

## Resources

* **cSQLServerJDBCXA** enables JDBC XA transactions on target machine.

### cSQLServerJDBCXA

* **Ensure**: (Required) Ensures that JDBC XA is Present or Absent on the machine.
* **Version**: (Key) The version of SQL Server (e.g. "v2008", "v2012")
* **InstanceName**: (Required) The SQL Server instance name
* **SQLServerPort**: (Optional) The SQL Server port to connect if using the default SQL Server instance (i.e. MSSQLSERVER)
* **SqlAdministratorCredential**: (Required) Credential for the SQL Server
* **SourcePath**: UNC or local file path to the directory of the sqljdbc executable file
* **SourcePathCredential**: (Optional) Credential to be used to map sourcepath if a remote share is being specified.

## Versions

### 1.0.0

* Initial release with the following resources 
    - cSQLServerJDBCXA

## Testing
Tested successfully on SQL Server 2012 Standard Edition running on Windows Server 2012 R2

## Source Files

The installation depents on source files that you'll need to download.  This has been tested with: sqljdbc_4.0.2206.100_enu.exe which you can download from: https://www.microsoft.com/en-us/download/details.aspx?id=11774

## Examples

### Enable JDBC XA

This configuration will enable JDBC XA on an existing SQL Server instance

Note: This requires the additional DSC modules:
* xPsDesiredStateConfiguration

Note: _You should NOT use PSDscAllowPlainTextPassword (unless is for testing).  See this article on how to properly secure MOF files:_ https://msdn.microsoft.com/en-us/powershell/dsc/secureMOF

```powershell
Configuration SQLServerXA
{
    param
    (
        [Parameter(Mandatory)]
        [PSCredential]
        $InstallCredential,

        [Parameter(Mandatory)]
        [PSCredential]
        $SACredential
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DSCResource -ModuleName 'cSQLServerJDBCXA'

    node localhost {
        cSQLServerJDBCXA "RDBMS"
        {
            Ensure = 'Present'
            InstanceName = 'DEV01'
            Version = 'v2012'
            SqlAdministratorCredential = $SACredential
            SourcePath = 'C:\Media\sqljdbc_4.0.2206.100_enu.exe'
            PsDscRunAsCredential = $installCredential
        }
    }
}

$configData = @{
    AllNodes = @(
        @{
            NodeName = "localhost"
            PSDscAllowPlainTextPassword = $true
        }
    )
}

$installCredential = (Get-Credential -UserName "Administrator" -Message "Enter the credentials of a Windows Administrator of the target server")
$saCredential = (Get-Credential -UserName "sa" -Message "Enter the credentials of the SQL Server Administrator - optional")
SQLServerXA -ConfigurationData $configData -InstallCredential $installCredential -SACredential $saCredential
Start-DscConfiguration -ComputerName localhost -Wait -Force -Verbose SQLServerXA
```
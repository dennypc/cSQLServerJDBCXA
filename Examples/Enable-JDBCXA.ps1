#requires -Version 5

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
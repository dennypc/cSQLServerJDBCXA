##############################################################################################################
########                                MS SQL Server JDBC XA CmdLets                                #########
##############################################################################################################

enum SQLServerVersion {
    v2014
    v2012
    v2008
}

# Global Constants
$XA_DLL_FILE = "sqljdbc_xa.dll"

##############################################################################################################
# Enable-XATransactions
#   Enables XA Transaction to be used with JDBC drivers
##############################################################################################################
Function Enable-XATransactions {
    param (
        [parameter(Mandatory = $true)]
        [SQLServerVersion] $Version,

		[String] $JDBCDriverPath,

        [parameter(Mandatory = $true)]
		[String] $InstanceName,
        
        [parameter(Mandatory = $false)]
		[String] $SQLServerPort,

        [System.Management.Automation.PSCredential] $SourcePathCredential,

        [System.Management.Automation.PSCredential] $SqlAdministratorCredential
	)

    $SQLBinPath = Get-SQLServerBinRoot -InstanceName $InstanceName
    try {
        if (($JDBCDriverPath.StartsWith("\\")) -and (!(Test-Path($JDBCDriverPath)))) {
            $networkShare = $true
        }
    } catch [System.UnauthorizedAccessException] {
        $networkShare = $true
    }

    if ($networkShare) {
        Write-Verbose "Network Share detected, need to map"
        NetUse -SharePath $JDBCDriverPath -SharePathCredential $SourcePathCredential -Ensure "Present" | Out-Null
    }
    
    try {
        if ((Test-Path($JDBCDriverPath)) -and ($SQLBinPath -ne $null) -and (Test-Path($SQLBinPath))) {
            Write-Verbose "Enabling SQL JDBC XA"
            $jdbcTemp = "$env:TEMP\sqljdbc\"
            if (Test-Path($jdbcTemp)) {
                Write-Verbose "Deleting existing SQL Server JDBC Driver temp directory: $jdbcTemp"
                Remove-Item $jdbcTemp -Recurse -Force
            }

            New-Item -ItemType directory -Path $jdbcTemp | Out-Null

            & $JDBCDriverPath "/auto" $jdbcTemp | Out-Null

            $XADir = Join-Path -Path $jdbcTemp -ChildPath "sqljdbc_*/enu/xa/"

            if (Test-Path($XADir)) {
                $XADir = (Get-Item($XADir)).FullName
                #Copy 
                $XADLLFile = $null
                if ([System.Environment]::Is64BitOperatingSystem) {
                    $XADLLFile = Join-Path -Path $XADir -ChildPath "x64/$XA_DLL_FILE"    
                } else {
                    $XADLLFile = Join-Path -Path $XADir -ChildPath "x86/$XA_DLL_FILE"
                }
                
                Copy-Item -Path $XADLLFile -Destination $SQLBinPath -Force

                Restart-SQLServerService -InstanceName $InstanceName

                $XAInstallSQLFile = Join-Path -Path $XADir -ChildPath "xa_install.sql"
                if (Test-Path($XAInstallSQLFile)) {
                    $sqlCmdPath = Get-SQLCmdPath $InstanceName
                    
                    $sqlInstancePath = "$env:COMPUTERNAME"
                    if ($InstanceName -eq "MSSQLSERVER") {
                        if ($SQLServerPort) {
                            $sqlInstancePath = "tcp:$env:COMPUTERNAME,$SQLServerPort"
                        } else {
                            $sqlInstancePath = "tcp:$env:COMPUTERNAME,1433"
                        }
                    } else {
                        $sqlInstancePath = "$env:COMPUTERNAME\$InstanceName"
                    }

                    if ($SqlAdministratorCredential) {
                        Write-Verbose "Running xa_install.sql via SQLCMD.EXE with SA account"
                        $saPwd = $SqlAdministratorCredential.GetNetworkCredential().Password
                        $saUserName = $SqlAdministratorCredential.UserName
                        & $sqlCmdPath "-i" $XAInstallSQLFile "-S" $sqlInstancePath "-U" $saUserName "-P" $saPwd | Write-Verbose
                    } else {
                        Write-Verbose "Running xa_install.sql via SQLCMD.EXE with Run Credentials"
                        & $sqlCmdPath "-E" "-i" $XAInstallSQLFile "-S" $sqlInstancePath | Write-Verbose
                    }
                } else {
                    Write-Error "Unable to locate xa_install.sql"
                }

                Write-Verbose "Setting MSDTC Security XA Transactions to 1"
                Set-ItemProperty -Path HKLM:\Software\Microsoft\MSDTC\Security -Name XaTransactions -Value 1

                Restart-SQLServerService -InstanceName $InstanceName
            }

            #clean up
            $rmjob = Start-Job { param($tdir) Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue } -ArgumentList $jdbcTemp
            Wait-Job $rmjob -Timeout 300 | Out-Null
            Stop-Job $rmjob | Out-Null
            Receive-Job $rmjob | Out-Null
            Remove-Job $rmjob | Out-Null
            if (Test-Path($jdbcTemp)) {
                Write-Warning "Unable to clean up installation files.  Please manually delete the files at: $jdbcTemp"
            }
        } else {
            Write-Error "Unable to locate JDBCDriverPath: $JDBCDriverPath or SQLBinPath: $SQLBinPath"
        }
    }
    finally {
        if ($networkShare) {
            NetUse -SharePath $JDBCDriverPath -SharePathCredential $SourcePathCredential -Ensure "Absent" | Out-Null
        }
    }
}

##############################################################################################################
# Get-SQLServerBinRoot
#   Returns the path to the SQL Server Bin folder for the SQL Server Instance specified
##############################################################################################################
Function Get-SQLServerBinRoot {
    param ([parameter(Mandatory = $true)] [System.String] $InstanceName)

    $SQLBinPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$InstanceName\Setup\").SQLBinRoot

    Return $SQLBinPath
}

##############################################################################################################
# Get-SQLCmdPath
#   Returns the path to the SQL Server SQLCMD.exe for the SQL Server Instance specified
##############################################################################################################
Function Get-SQLCmdPath {
    param ([parameter(Mandatory = $true)] [System.String] $InstanceName)

    [string] $sqlCmdPath = $null
    [string] $sqlInstDir = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$InstanceName\Setup\").SqlProgramDir
    [string] $sqlVersion = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL*.$InstanceName\Setup\").Version

    if ($sqlVersion.StartsWith("11.")) {
        $sqlCmdPath = Join-Path $sqlInstDir "110\Tools\Binn\SQLCMD.exe"
    } elseif ($sqlVersion.StartsWith("10.")) {
        $sqlCmdPath = Join-Path $sqlInstDir "100\Tools\Binn\SQLCMD.exe"
    } else {
        Write-Warning "Unsupported SQL Server Version"
    }

    if ($sqlCmdPath -and (!(Test-Path $sqlCmdPath))) {
        $sqlCmdPath = $null
    }

    Return $sqlCmdPath
}

##############################################################################################################
# Get-SQLServerService
#   Retrieves the Windows Service Name for the SQL Server Instance specified
##############################################################################################################
Function Get-SQLServerService() {
    param (
		[parameter(Mandatory = $true)]
		[System.String]
		$InstanceName
	)
    
    $list = Get-Service -Name MSSQL*
    $svcName = $null

    if ($InstanceName -eq "MSSQLSERVER") {
        if ($list.Name -contains "MSSQLSERVER") {
            $svcName = $InstanceName
        }
    } elseif ($list.Name -contains $("MSSQL$" + $InstanceName)) {
        $svcName = "MSSQL$" + $InstanceName
    }

    $retSvc = $list | Where-Object { $_.Name -eq $svcName }

    return $retSvc
}

##############################################################################################################
# Restart-SQLServerService
#   Restarts SQL Server via Windows Services
##############################################################################################################
Function Restart-SQLServerService {
    param (
		[parameter(Mandatory = $true)]
		[System.String]
		$InstanceName
	)

    # Re-start SQL Server
    Write-Verbose "Restarting SQL Server via Windows Service"
    $sqlServerSvc = Get-SQLServerService -InstanceName $InstanceName
    if (($sqlServerSvc -ne $null) -and ($sqlServerSvc.Status -ne "Running")) {
        Start-Service $sqlServerSvc
    } elseif ($sqlServerSvc -ne $null) {
        Restart-Service $sqlServerSvc -Force
    }

    if (($sqlServerSvc -ne $null) -and ($sqlServerSvc.DependentServices)) {
        foreach($sqlDepSvc in $sqlServerSvc.DependentServices) {
            Start-Service $sqlDepSvc
        }
    }
}

##############################################################################################################
# NetUse
#   Mounts or Unmounts a file share via "net use" using the specified credentials 
##############################################################################################################
Function NetUse {
    param (   
        [parameter(Mandatory = $true)]
        [string] $SharePath,
        
        [parameter(Mandatory = $false)]
        [PSCredential] $SharePathCredential,
        
        [string] $Ensure = "Present",
        
        [switch] $MapToDrive
    )
    
    [string] $randomDrive = $null

    Write-Verbose -Message "NetUse set share $SharePath ..."

    if ($Ensure -eq "Absent") {
        $cmd = 'net use "' + $SharePath + '" /DELETE'
    } else {
        $credCmdOption = ""
        if ($SharePathCredential) {
            $cred = $SharePathCredential.GetNetworkCredential()
            $pwd = $cred.Password
            $user = $cred.UserName
            if ($cred.Domain) {
                $user = $cred.Domain + "\" + $cred.UserName
            }
            $credCmdOption = " $pwd /user:$user"
        }
        
        if ($MapToDrive) {
            $randomDrive = Get-AvailableDrive
            $cmd = 'net use ' + $randomDrive + ' "' + $SharePath + '"' + $credCmdOption
        } else {
            $cmd = 'net use "' + $SharePath + '"' + $credCmdOption
        }
    }

    Invoke-Expression $cmd | Out-Null
    
    Return $randomDrive
}
# Import SQL Server  Module
Import-Module $PSScriptRoot\cSQLServerJDBCXAUtils.psm1 -ErrorAction Stop

enum Ensure {
    Absent
    Present
}

enum SQLServerVersion {
    v2014
    v2012
    v2008
}

<#
   DSC resource to enable JBDC XA transactions on SQL Server
   Key features: 
    - Enable MSDTC
    - Installs SQLJDBC_XA.dll 
#>

[DscResource()]
class cSQLServerJDBCXA {
    [DscProperty(Mandatory)]
    [Ensure] $Ensure
    
    [DscProperty(Key)]
    [string] $InstanceName
    
    [DscProperty(Key)]
    [SQLServerVersion] $Version
    
    [DscProperty()]
    [String] $SQLServerPort
    
    [DscProperty()]
    [System.Management.Automation.PSCredential] $SqlAdministratorCredential
    
    [DscProperty()]
    [String] $SourcePath
    
    [DscProperty()]
    [System.Management.Automation.PSCredential] $SourcePathCredential
    
    [string] $XA_DLL_FILE = "sqljdbc_xa.dll"
    
    # Sets the desired state of the resource.
    [void] Set() {
        try {
            if ($this.Ensure -eq [Ensure]::Present) {
                [string] $sqlInstanceName = $this.InstanceName
                Write-Verbose -Message "Enabling JDBC XA on SQL Server Instance: $sqlInstanceName"
                Enable-XATransactions -Version $this.Version -InstanceName $this.InstanceName -SQLServerPort $this.SQLServerPort `
                    -JDBCDriverPath $this.SourcePath -SourcePathCredential $this.SourcePathCredential `
                    -SqlAdministratorCredential $this.SqlAdministratorCredential -ErrorAction Stop -Verbose
            } else {
                Write-Verbose "Disable JDBC XA has not yet been implemented"
            }
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
    
    # Tests if the resource is in the desired state.
    [bool] Test() {
        Write-Verbose "Checking if JDBC XA transaction support is configured correctly"
        $xaConfiguredCorrectly = $false
        $xaRsrc = $this.Get()
        
        if (($xaRsrc.Ensure -eq $this.Ensure) -and ($xaRsrc.Ensure -eq [Ensure]::Present)) {
            $xaConfiguredCorrectly = $true
        } elseif (($xaRsrc.Ensure -eq $this.Ensure) -and ($xaRsrc.Ensure -eq [Ensure]::Absent)) {
            $xaConfiguredCorrectly = $true
        }

        if (!($xaConfiguredCorrectly)) {
            Write-Verbose "JDBC XA not configured correctly"
        }
        
        return $xaConfiguredCorrectly
    }
    
    # Gets the resource's current state.
    [cSQLServerJDBCXA] Get() {
        $RetEnsure = [Ensure]::Absent
        $XAEnabled = $false
        $sqlbin = Get-SQLServerBinRoot -InstanceName $this.InstanceName

        if (($sqlbin -ne $null) -and (Test-Path($sqlbin))) {
            $xaDLL = Join-Path -Path $sqlbin -ChildPath $this.XA_DLL_FILE
            if (Test-Path($xaDLL)) {
                Write-Verbose "JDBC XA DLL file found at: $xaDLL"
                $msdtcSec = Get-ItemProperty -Path HKLM:\Software\Microsoft\MSDTC\Security
                 Write-Verbose ("XA Transactions in MSDTC set to: " + $msdtcSec.XaTransactions)
                if ($msdtcSec.XaTransactions -eq "1") {
                    $XAEnabled = $true
                }
            }
        } else {
            Write-Error "Unable to get SQL Server Bin Root for instance. SQL Server Instance is required"
        }

        if ($XAEnabled) {
            $RetEnsure = [Ensure]::Present
        }

        $returnValue = @{
            Ensure = $RetEnsure
        }
        
        return $returnValue
    }
}
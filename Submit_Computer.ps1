#requires -version 4
<#
.SYNOPSIS
  Crawl an ActiveDirectory for available Computerobjects.

.DESCRIPTION
  The script crawls an ActiveDirectory for available Computerobjects and submits them to an IDB.

.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>

.INPUTS
  NONE

.OUTPUTS Log File
  The script log file stored in C:\Windows\Temp\<name>.log

.NOTES
  Version:        1.0
  Author:         Felix Kronlage
  Creation Date:  10/09/2015
  Purpose/Change: Initial script development

.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>

  <Example explanation goes here>
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
#$ErrorActionPreference = 'SilentlyContinue'

#Import PSLogging Module
#Import-Module PSLogging
#Dot Source required Function Libraries

. "$PSScriptRoot\contrib\Function-Write-Log.ps1"
. "$PSScriptRoot\contrib\Get-PendingUpdate.ps1"

#Import ActiveDirectory Module
Import-Module ActiveDirectory

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$LogPath = "$PSScriptRoot\idbad.log"

$ConfigPath = "$PSScriptRoot\config.xml"

Write-Log -Path $LogPath -Message "Loading config $ConfigPath"
[xml]$XMLConfig = Get-Content "$ConfigPath"

$IDBUrl = $XMLConfig.Settings.IDBURL
$IDBApiToken = $XMLConfig.Settings.IDBApiToken
$ADFilter = $XMLConfig.Settings.ADFilter
[bool]$IgnoreSSL = [System.Convert]::ToBoolean($XMLConfig.Settings.IgnoreSSL)
[bool]$IDBCreateMachine = [System.Convert]::ToBoolean($XMLConfig.Settings.IDBCreateMachine)

Write-Log -Path $LogPath -Message "IDB Url: $IDBUrl"
Write-Log -Path $LogPath -Message "IDB Create Machine: $IDBCreateMachine"
Write-Log -Path $LogPath -Message "AD Filter: $ADFilter"
Write-Log -Path $LogPath -Message "Ignore SSL: $IgnoreSSL"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Ignore-SSLCertificates
{
   Write-Log -Path $LogPath -Message "Ignoring broken SSL Certificates"
    $Provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $Compiler = $Provider.CreateCompiler()
    $Params = New-Object System.CodeDom.Compiler.CompilerParameters
    $Params.GenerateExecutable = $false
    $Params.GenerateInMemory = $true
    $Params.IncludeDebugInformation = $false
    $Params.ReferencedAssemblies.Add("System.DLL") > $null
    $TASource=@'
        namespace Local.ToolkitExtensions.Net.CertificatePolicy
        {
            public class TrustAll : System.Net.ICertificatePolicy
            {
                public bool CheckValidationResult(System.Net.ServicePoint sp,System.Security.Cryptography.X509Certificates.X509Certificate cert, System.Net.WebRequest req, int problem)
                {
                    return true;
                }
            }
        }
'@ 
    $TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
    $TAAssembly=$TAResults.CompiledAssembly
    ## We create an instance of TrustAll and attach it to the ServicePointManager
    $TrustAll = $TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
    [System.Net.ServicePointManager]::CertificatePolicy = $TrustAll
}

Function Get-Pending-Updates-Per-Computer {
<#
 .SYNOPSIS
   Use the Get-PendingUpdates Cmdlet to get updates per Maschine and parse them

 .DESCRIPTION
   Submits machine information to an infrastructure database

 .PARAMETER ComputerName
   Mandatory. The name of the computer object you want to have the pending updates for.

 .INPUTS
   Parameters above
 #>
 [CmdletBinding()]

 Param ([Parameter(Mandatory=$true)]$ComputerName)

 $num_updates= 0;
 $num_sec_updates= 0;
 $updates= Get-PendingUpdate -Computer $ComputerName

 foreach ($update in $updates) {
    <# 
        Parse String and count:
        security-update++ if the title contains Security

    #>
    if ($update."Title" -match "Security") {
        $num_sec_updates++
    }

    $num_updates++

 }
 Write-Log -Path $LogPath -Message "1: $num_updates"
 return @{ "Updates"= $num_updates; "Security_Updates"= $num_sec_updates}

}

Function Submit-Computer {
 <#
  .SYNOPSIS
    Submits machine information to an infrastructure database

  .DESCRIPTION
    Submits machine information to an infrastructure database
  
  .PARAMETER Computer
    Mandatory. The computer object you want to submit.

  .INPUTS
    Parameters above

  .OUTPUTS
    NONE

  .NOTES
    Version:        1.0
    Author:         Felix Kronlage
    Creation Date:  13.10.2015
    Purpose/Change: Initial function development

  .EXAMPLE
    Submit-Computer -Computer ...
  #>
  [CmdletBinding()]
  
  Param ([Parameter(Mandatory=$true)]$Computer)
  
  $machine_data= Get-ADComputer -Identity $Computer -Property *
  $fqdn= $machine_data."DNSHostName"
  $os= $machine_data."OperatingSystem"
  $os_release= $machine_data."OperatingSystemVersion"
  $ip4= $machine_data."IPv4Address"

  $Updates= Get-Pending-Updates-Per-Computer($Computer."Name")

  $P_u= $Updates.Get_Item("Updates")
  $P_su= $Updates.Get_Item("Security_Updates")

  $createMachine = ""
  if ($IDBCreateMachine) {
    $createMachine = "true"
  } else {
    $createMachine = "false"
  }

  $json= "{
		    ""fqdn"":""$fqdn"",
            ""os"":""$os"",
            ""os_release"":""$os_release"",
            ""nics"":[{""ip_address"": {""addr"": ""$ip4"" }, ""name"": ""eth0""}],
            ""pending_updates"":""$P_u"",
            ""pending_security_updates"":""$P_su"",
            ""create_machine"":""$createMachine""
		    }"

  Write-Log -Path $LogPath -Message "Dumping the body: $json"
  try {
    Invoke-RestMethod -Method PUT -ContentType "application/json" -Body $json -Uri "${IDBUrl}/api/v2/machines?idb_api_token=${IDBApiToken}"
  } catch {
    $res_status = $_.Exception.Response.StatusCode
    Write-Log -Path $LogPath -Message "IDB returned: $res_status"
  }
  
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------=

if ($IgnoreSSL) {
    Ignore-SSLCertificates
}

$machines= Get-ADComputer -Filter $ADFilter

foreach ($machine in $machines) {
    Submit-Computer($machine)
}



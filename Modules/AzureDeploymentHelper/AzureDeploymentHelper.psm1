$Global:Environment = "AzureUsGovernment"

<#
    .SYNOPSIS
        Connects to Azure and sets the provided subscription.

    .PARAMETER SubscriptionId
        ID of subscription to use
#>

Function Split-Array {
	[CmdletBinding()]
	Param(
		$InputObject,
		[Int]$Parts,
		[Int]$Size,
		[ValidateSet("ByIndex","ByName")]
		$KeyType
	)
	If ($Parts) {$PartSize = [Math]::Ceiling($InputObject.Count/$Parts)}
	If ($Size) {
		$PartSize = $Size
		$Parts = [Math]::Ceiling($InputObject.Count/$Size)
	}
	$OutputObject = [Ordered]@{}
	For ($i=1; $i -le $Parts; $i++) {
		$start = (($i-1) * $PartSize)
		$End = ($i * $PartSize) - 1
		If ($end -ge $InputObject.Count) {$End = $InputObject.Count}
		If ($KeyType -eq "ByIndex") {
			If ($i -le 9) {$Key = ("GroupIndex[0{0}]" -f $i)}
			Else {$Key = ("GroupIndex[{0}]" -f $i)}
			$OutputObject.Add($Key,$InputObject[$start..$End])
		}
		ElseIf ($KeyType -eq "ByName") {
			$Key = Read-Host "Enter Key Name ($i of $parts)"
			Write-Verbose "Hash Table Key: $Key"
			$OutputObject.Add($Key,$InputObject[$start..$End])
		}
	}
	Return $OutputObject
}
function Get-AzureConnection {
    [CmdletBinding()]
    Param (
        [ValidateSet("AzureUSGovernment","AzureCloud","AzureChinaCloud","AzureGermanCloud")]
        [System.String]$Environment = "AzureUSGovernment"
    )

    If ($null -eq (Get-AzureRmContext).Account) {
        $Context = Login-AzureRmAccount -Environment $Environment -ErrorAction SilentlyContinue
        If ($Context) {Return $true}
        Else {Return $false}
    }
    Else {Return $true}
}

Function Show-Menu {
    Param(
        [string]$Menu,
        [string]$Title = $(Throw [System.Management.Automation.PSArgumentNullException]::new("Title")),
        [switch]$ClearScreen,
        [Switch]$DisplayOnly,
        [ValidateSet("Full","Mini","Info")]
        $Style = "Full",
        [ValidateSet("White","Cyan","Magenta","Yellow","Green","Red","Gray","DarkGray")]
        $Color = "Gray"
    )
    if ($ClearScreen) {[System.Console]::Clear()}

    If ($Style -eq "Full") {
        #build the menu prompt
       $menuPrompt = "/" * (95)
        $menuPrompt += "`n`r////`n`r//// $Title`n`r////`n`r"
        $menuPrompt += "/" * (95)
        $menuPrompt += "`n`n"
    }
    ElseIf ($Style -eq "Mini") {
        #$menuPrompt = "`n"
        $menuPrompt = "\" * (80)
        $menuPrompt += "`n\\\\  $Title`n"
        $menuPrompt += "\" * (80)
        $menuPrompt += "`n"
    }
    ElseIf ($Style -eq "Info") {
        #$menuPrompt = "`n"
        $menuPrompt = "-" * (80)
        $menuPrompt += "`n-- $Title`n"
        $menuPrompt += "-" * (80)
    }

    #add the menu
    $menuPrompt+=$menu

    [System.Console]::ForegroundColor = $Color
    If ($DisplayOnly) {Write-Host $menuPrompt}
    Else {Read-Host -Prompt $menuprompt}
    [system.console]::ResetColor()
}
Function Find-AzureSubscription {
    [CmdletBinding()]
    Param()
    Write-Verbose "Getting Azure Subscriptions..."
    If (@(Get-AzureConnection -Environment $Global:Environment)) {
        $Subs = Get-AzureRmSubscription | Select Name,Id
        Write-Verbose ("Found {0} Azure Subscriptions" -f $Subs.Count)
        $SubSelection = (@"
`n
"@)
        If (($Subs | Measure-Object).Count -eq 1) {
            Write-Warning ("SINGLE Azure Subscription found, using: {0}" -f $Subs.Name)
            Return $Subs
        }
        Else {
            $SubRange = 0..(($Subs | Measure-Object).Count - 1)
            For ($i = 0; $i -lt ($Subs | Measure-Object).Count;$i++) {$SubSelection += " [$i] $($Subs[$i].Name)`n"}
            $SubSelection += "`n Please select a Subscription"

            Do {
                $SubChoice = Show-Menu -Title "Select an Azure Subscription" -Menu $SubSelection -Style Mini -Color Yellow
            }
            While (($SubRange -notcontains $SubChoice) -OR (-NOT $SubChoice.GetType().Name -eq "Int32"))
            Return $Subs[$SubChoice]
        }
    }
    Else {Return Write-Warning ("Unable to validate Azure Connection!")}
}

Function Select-ArmDeployment {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline=$true)]
        [System.Collections.Hashtable[]]$Data
    )
    Write-Debug "test"

}
<#
    .SYNOPSIS
        Starts a new Azure RM template deployment.

    .PARAMETER TemplateFile
        Path to ARM template

    .PARAMETER ResourceGroupName
        Name of resource group to deploy template file too

    .PARAMETER TemplateParameterObject
        Parameter objects for template
#>
function New-ArmDeployment
{
    [cmdletbinding()]
    Param
    (
        [parameter(mandatory = $true)]
        $DeploymentName,
    
        [parameter(mandatory = $true)]
        $TemplateFile,

        [parameter(mandatory = $true)]
        $ResourceGroupName,

        [parameter(mandatory = $true)]
        $Subscription,

        [parameter(mandatory = $true)]
        $TemplateParameterObject
    )
    
    Set-AzureRmContext -SubscriptionID $Subscription | out-null
    Set-AzureRmDefault -ResourceGroupName $ResourceGroupName | out-null
    $Context = Get-AzureRmContext 
    
    Write-Verbose "Starting $DeploymentName"

    return New-AzureRmResourceGroupDeployment -Name $DeploymentName `
                                              -ResourceGroupName $ResourceGroupName `
                                              -DefaultProfile $Context `
                                              -TemplateFile $TemplateFile `
                                              -TemplateParameterObject $TemplateParameterObject `
                                              -Force `
                                              -Verbose `
                                              -Asjob `
                                              
}
function Get-KeyVaultSecret  {
    Param
    (
        [parameter(mandatory = $true)]
        $Subscription,
        [parameter(mandatory = $true)]
        $VaultName,
        [parameter(mandatory = $true)]
        $SecretName
    )

    $StartingSub = (Get-AzureRmContext).Subscription.ID

    If ($StartingSub -ne $Subscription) {
        Write-Host "Changing to Sub $($Subscription)"
        Set-AzureRmContext -SubscriptionId $Subscription | out-null
    }

    Write-Host "Retrieving Secret $($SecretName)"
    $Secret = $null
    $Secret = (Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SecretName).SecretValueText
    If ($Secret){Write-Host "Success"} Else {Write-Host "Failed to Retrieve $($SecretName)"}

    If ((Get-AzureRmContext).Subscription.ID -ne $StartingSub) {
        Write-Host "Changing back to starting Subscription $($StartingSub)"
        Set-AzureRmContext -SubscriptionId $StartingSub | out-null
    }

    return $Secret

}


Function New-KeyVaultCSVTemplate {

    #Sample Data
    $Item = New-Object PSObject -Property @{
        Subscription = "ed347077-d367-4401-af11-a87b73bbae0e"
        ResourceGroupName = "Prod-RG"
        VaultName = "Agile-KV"
        SecretName = "Prod-F5-azureuser"
        ContentType = "Prod-F5-azureuser"
        SecretValue = "MyPassword"
    }
    
    $Item | 
        Select-Object -Property Subscription,ResourceGroupName,VaultName,SecretName,ContentType,SecretValue | 
        Export-Csv -Path KeyVaultBulkLoad.csv -NoTypeInformation    
}

Function Add-KeyVaultSecret {

    $Secrets = Import-Csv -Path KeyVaultBulkLoad.csv             

    foreach ($Secret in $Secrets) {
    
        Write-Host "Adding Secret for $($Secret.SecretName) to KeyVault $($Secret.VaultName) in $($Secret.ResourceGroupName)"        
        $secretvalue = $null
        $secretvalue = ConvertTo-SecureString $($Secret.SecretValue) -AsPlainText -Force
        Set-AzureKeyVaultSecret -VaultName $Secret.VaultName -Name $Secret.SecretName -SecretValue $SecretValue -ContentType $Secret.ContentType 
             
    }
  

}

function Add-KeyVaultSecret {
    $Secrets = Import-Csv -Path KeyVaultBulkLoad.csv             


    foreach ($Secret in $Secrets) {
    
        Write-Host "Adding Secret for $($Secret.SecretName) to KeyVault $($Secret.VaultName) in $($Secret.ResourceGroupName)"        
        $secretvalue = $null
        $secretvalue = ConvertTo-SecureString $($Secret.SecretValue) -AsPlainText -Force
        Set-AzureKeyVaultSecret -VaultName $Secret.VaultName -Name $Secret.SecretName -SecretValue $SecretValue -ContentType $Secret.ContentType 
    }
    
}

Function New-AzureLabDeployment {
    <#
        .SYNOPSIS
            Deploys Azure resources via ARM templates
    #>

    [CmdletBinding()]
    Param (
        [ValidateSet("AzureUSGovernment","AzureCloud","AzureChinaCloud","AzureGermanCloud")]
        [System.String]$Environment = "AzureUSGovernment"
    )

    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()


    #Move to the location of the script if you not threre already
    Write-Host "Set-Location to script's directory..."
    $Script:Path = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition) 
    Set-Location $Script:Path

    #If not logged in to Azure, start login
    $AzureConnectionStatus = Get-AzureConnection -Environment $Environment
    If (-NOT $AzureConnectionStatus) {Write-Warning "Unable to verify Azure Connection Status!"; Break}
    Else {Write-Verbose "Azure Connection Verified!"}

    #Get the Azure Subscription to work from
    $objAzureSub = Find-AzureSubscription -Verbose

    # Get the configuration data
    Write-Debug "Loading Configuration Data..."
    $Configdata = . ("{0}\Environments\Data.ps1" -f $Script:Path)
    #$configData = & $ConfigurationPath

    $labsize = [Ordered]@{
        Small = [Ordered]@{
            VMs = 9
            ResourceGroups = 3
            VMsPerRG = 3
            AVSetsPerRG = 1
            VMsPerAS = 2
            NonASVMsPerRG = 1
        }
        Medium = [Ordered]@{
            VMs = 24
            ResourceGroups = 4
            VMsPerRG = 6
            AVSetsPerRG = 2
            VMsPerAS = 2
            NonASVMsPerRG = 2
        }
        Large = [Ordered]@{
            VMs = 63
            ResourceGroups = 7
            VMsPerRG = 9
            AVSetsPerRG = 2
            VMsPerAS = 4
            NonASVMsPerRG = 1
        }
    }

    #Select Deployments
    Write-Host "Pop Up - Select Select Deployments in Out-Gridview"
    $DeploymentFilters = $Configdata.Deployments | ForEach-Object {$_.DeploymentName} | Out-GridView -Title "Select Deployments" -OutputMode Multiple

    # Apply filter to only deploy the correct Deployments.
    $deployDeployment = @()
    if($DeploymentFilters)
    {
        Write-Verbose "Appling filter to Deployments being deployed"

        foreach($DeploymentFilter in $DeploymentFilters)
        {
            # find any vm that has a name like the VM filter and add it to $deployDeployment unless it is already there
            $deployDeployment += $configData.Deployments.Where{ `
                ($_.DeploymentName -like $DeploymentFilter) `
                -and ($deployDeployment.DeploymentName -notcontains $_.DeploymentName)`
            }
        }
    }
    else
    {
        Write-Verbose "No filter applied, deploying all Deployments"

        $deployDeployment = $configData.Deployments
    }

    # Start Deployments
    Write-Output "`n$($deployDeployment.Count) Deployments Selected"

    Write-Host "`nType ""Deploy"" to start Deployments, or Ctrl-C to Exit" -ForegroundColor Green
    $HostInput = $Null
    $HostInput = Read-Host "Final Answer" 
    If ($HostInput -ne "Deploy" ) {
        Write-Host "Exiting"
        break
    }

    Write-Output "Starting $($deployDeployment.Count) Deployments"

    $deploymentJobs = @()
    foreach($Deployment in $deployDeployment)
    {
        Write-Output "Deploying $($Deployment.DeploymentName)"

        $deploymentJobs += @{
            Job = New-ArmDeployment -TemplateFile $Deployment.TemplateFilePath `
                                    -DeploymentName $Deployment.DeploymentName `
                                    -ResourceGroupName $Deployment.ResourceGroupName `
                                    -Subscription $Deployment.Subscription `
                                    -TemplateParameterObject $Deployment.Parameters `
                                    -Verbose
            DeploymentName = $Deployment.DeploymentName
        }

        # Pause for 5 seconds otherwise we can have name collision issues
        Start-Sleep -Second 5
    }

    do
    {
        $jobsStillRunning = $false
        foreach($deploymentJob in $deploymentJobs)
        {
            Receive-Job -Job $deploymentJob.Job

            $currentStatus = Get-Job -Id $deploymentJob.Job.Id

            if(@("NotStarted", "Running") -contains $currentStatus.State)
            {
                $jobsStillRunning = $true
                Start-Sleep -Second 10
            }
        }
    }
    while($jobsStillRunning)

    If ((Get-AzureRmContext).Subscription.ID -ne $StartingSub) {
        Write-Host "Changing back to starting Subscription $($StartingSub)"
        Set-AzureRmContext -SubscriptionId $StartingSub 
    }

    Write-Output "Total Elapsed Time: $($elapsed.Elapsed.ToString())"

    $elapsed.Stop()

}
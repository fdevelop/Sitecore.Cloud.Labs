### Sitecore Cloud Labs - Upload Sitecore License to Sitecore on Azure Web Apps / Managed Cloud
### Useful for cases when previous license got expired or license file was upgraded with new keys


Param(
    [Parameter(Mandatory=$True)]$subscriptionId,
    [Parameter(Mandatory=$True)]$resourceGroupName, 
    [Parameter(Mandatory=$True)]$pathToLicenseFile
)


function Get-PublishingProfileCredentials($resourceGroupName, $webAppName){
 
    $resourceType = "Microsoft.Web/sites/config"
    $resourceName = "$webAppName/publishingcredentials"
 
    $publishingCredentials = Invoke-AzureRmResourceAction -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ResourceName $resourceName -Action list -ApiVersion 2015-08-01 -Force
 
    return $publishingCredentials
}
 
function Get-KuduApiAuthorisationHeaderValue($resourceGroupName, $webAppName){
 
    $publishingCredentials = Get-PublishingProfileCredentials $resourceGroupName $webAppName
 
    return ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $publishingCredentials.Properties.PublishingUserName, $publishingCredentials.Properties.PublishingPassword))))
}

function Upload-FileToWebApp($kuduApiAuthorisationToken, $webAppName, $relPath, $fileName, $localPath, $onlyIfExists ){
 
    $kuduApiUrl = "https://$webAppName.scm.azurewebsites.net/api/vfs/$relPath/$fileName"
    
    $skipUpload = $False

    try {
        $resultExists = Invoke-RestMethod -Uri $kuduApiUrl -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} -Method GET
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -gt 400 -and $onlyIfExists -eq $True) {
            $skipUpload = $True
        }
    }
     
    if (!$skipUpload) {
        $result = Invoke-RestMethod -Uri $kuduApiUrl `
                        -Headers @{"Authorization"=$kuduApiAuthorisationToken;"If-Match"="*"} `
                        -Method PUT `
                        -InFile $localPath `
                        -ContentType "multipart/form-data"
    } else {
        Write-Host " [INFO: upload via $relPath skipped, because no original license.xml was found] " -NoNewline -ForegroundColor Yellow
    }
}

function Upload-SitecoreLicense($subscriptionId, $resourceGroupName, $pathToLicenseFile) {
 
    if(![System.IO.File]::Exists($pathToLicenseFile)){
        Write-Error -Message "File $($pathToLicenseFile) does not exist!" -ErrorAction Stop
    }

    Write-Host "Selecting subscription $($subscriptionId)..."

    Select-AzureRmSubscription -SubscriptionId $subscriptionId

    Write-Host "Selecting web apps..."
    
    $webApps = Get-AzureRmWebApp -ResourceGroupName $resourceGroupName

    $webApps | % {
        $accessToken = Get-KuduApiAuthorisationHeaderValue $resourceGroupName $_.Name

        Write-Host "Uploading license.xml to $($_.Name)" -NoNewline
        Upload-FileToWebApp $accessToken $_.Name "site/wwwroot/App_data" "license.xml" $pathToLicenseFile $False
        Write-Host -f Green " [Done]"

        if ($_.Name.EndsWith("-ma-ops") -or $_.Name.EndsWith("-ma-rep") -or $_.Name.EndsWith("-xc-collect") `
            -or $_.Name.EndsWith("-xc-search") -or $_.Name.EndsWith("-xc-refdata")) {

            Write-Host "Uploading license.xml to $($_.Name)" -NoNewline
            Upload-FileToWebApp $accessToken $_.Name "site/wwwroot/App_data/jobs/continuous/AutomationEngine/App_Data" "license.xml" $pathToLicenseFile $True
            Upload-FileToWebApp $accessToken $_.Name "site/wwwroot/App_data/jobs/continuous/IndexWorker/App_Data" "license.xml" $pathToLicenseFile $True
            Write-Host -f Green " [Done]"

        }
    }
}

## Script listing

Upload-SitecoreLicense $subscriptionId $resourceGroupName $pathToLicenseFile
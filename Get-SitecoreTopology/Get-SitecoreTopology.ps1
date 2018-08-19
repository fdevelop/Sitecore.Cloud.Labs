Param(
    $subscriptionId,
    $resourceGroupName
)

function New-SitecoreResourceObject($category, $name, $location, $sizing, $customData) {

    # Write-Host "New iteration ... $name ... "

    $hash = @{            
        Category        =   $category  + "   "
        Name            =   $name      + "   "
        Location        =   $location  + "   "          
        Sizing          =   $sizing    + "   "
        CustomData      =   $customData
    }                           
                                    
    $Object = New-Object PSObject -Property $hash

    return $Object
}

Select-AzureRmSubscription -SubscriptionId $subscriptionId

# Web Apps 
$webApps = @()
$webApps = $webApps + (Get-AzureRmAppServicePlan -ResourceGroupName $resourceGroupName | % { New-SitecoreResourceObject -category "Web App" -name $_.Name -location $_.Location -sizing "$($_.Sku.Capacity) x $($_.Sku.Size)" -customData "Number of Sites on App Plan: $($_.NumberOfSites)" })

# SQL and Search
$sqlDatabases = @()
foreach ($ss in Get-AzureRmSqlServer -ResourceGroupName $resourceGroupName) {

    $sqlDatabases = $sqlDatabases + `
        (Get-AzureRmSqlDatabase -ResourceGroupName $($ss.ResourceGroupName) -ServerName $($ss.ServerName) `
            | % { New-SitecoreResourceObject -category "SQL Database" -name "$($_.DatabaseName)" -location $_.Location -sizing $_.CurrentServiceObjectiveName -customData "Server Name: $($_.ServerName)" } )

}

# Search
$search = @()
foreach ($searchResource in Find-AzureRmResource -ResourceType "Microsoft.Search/searchServices") {

    if ($($searchResource.ResourceGroupName) -ne $resourceGroupName) {
        continue
    }

    $search = $search + (Get-AzureRmResource -ResourceType "Microsoft.Search/searchServices" `
        -ResourceGroupName $($searchResource.ResourceGroupName) -ResourceName $searchResource.Name `
        -ApiVersion 2015-08-19 `
        | % { New-SitecoreResourceObject -category "Search" -name $_.ResourceName -location $_.Location -sizing "SKU: $($_.Sku), $($_.Properties.replicaCount) replicas, $($_.Properties.PartitionCount) partitions" -customData "(N/A)" } )

}

# Redis
$redis = @()
$redis = $redis + (Get-AzureRmRedisCache -ResourceGroupName $resourceGroupName | % { New-SitecoreResourceObject -category "Redis" -name $_.Name -location $_.Location -sizing "$($_.Sku), $($_.Size)" -customData "(N/A)"})

# App Insights
$appInsights = @()

foreach ($ai in Get-AzureRmApplicationInsights -ResourceGroupName $resourceGroupName) {

    $appInsights = $appInsights + (Get-AzureRmApplicationInsights -ResourceGroupName $resourceGroupName -Name $ai.Name -Full `
        | % { New-SitecoreResourceObject -category "AppInsights" -name $_.Name -location $_.Location -sizing "$($_.PricingPlan)" -customData "AppType: $($_.ApplicationType)" })

}

# Final Output

$webApps + $sqlDatabases + $search + $redis + $appInsights | Format-Table Category, Name, Location, Sizing, CustomData -AutoSize
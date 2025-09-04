## How To Use
<#
1. Fill in the Script Configuration section with your API credentials.
2. Run the script up to step 2.
3. Find the desired Base GUID from the output.
4. Manually set the Base GUID to look up the sites.
5. Run the rest of the script (from step 3.) to the to retrieve the Site GUIDs.
6. Manually search for the Site GUID and save it to use in the connector configuration.
#>

# 1. Script Configuration
$actionContext = @{
    Configuration = @{
        baseUrl      = 'https://ipassan.com'
        clientID     = 'your-client-id'
        clientSecret = 'your-client-secret'
    }
}

#region Function
function Get-AuthToken {
    [CmdletBinding()]
    param()
    try {
        $headers = @{
            'Content-Type' = 'application/x-www-form-urlencoded'
        }
        $body = @{
            grant_type    = 'client_credentials'
            scope         = 'all'
            client_id     = $actionContext.Configuration.clientID
            client_secret = $actionContext.Configuration.clientSecret
        }
        $splatToken = @{
            Uri     = "$($actionContext.Configuration.baseUrl)/api/v1/token"
            Body    = $body
            Method  = 'POST'
            Headers = $headers
        }
        $tokenResponse = Invoke-RestMethod @splatToken
        Write-Output $tokenResponse.access_token
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion Function


# Get the authorization token and set the headers.
$token = Get-AuthToken
$headers = @{
    Authorization = "Bearer $token"
}

# First, retrieve the Base GUID.
$limit = 50
$offset = 0
$baseList = [System.Collections.Generic.List[object]]::new()
do {
    $splatParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/api/v1/admin/base?limit=$limit&offset=$offset"
        Method  = 'GET'
        Headers = $headers
    }
    $subSetList = Invoke-RestMethod @splatParams
    if ($null -ne $subSetList.data) {
        $baseList.AddRange($subSetList.data)
    }
    $offset += $limit
} until ($null -eq $subSetList.next_cursor)

# 2. Look up the correct Base GUID.
$baseList | Select-Object -Property name, displayname, uuid | Format-Table

# 3. Manually set the Base GUID here after looking it up in the previous step.
$baseGUID = '94d7d865-7b99-4a49-a269-f7324480ec93'

#Then retrieve all sites using the previously retrieved Base GUID.
$limit = 50
$offset = 0
$siteList = [System.Collections.Generic.List[object]]::new()
do {
    $splatParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/api/v1/admin/base/$baseGUID/site?limit=$limit&offset=$offset"
        Method  = 'GET'
        Headers = $headers
    }
    $subSetList = Invoke-RestMethod @splatParams
    if ($null -ne $subSetList.data) {
        $siteList.AddRange($subSetList.data)
    }
    $offset += $limit
}until ($null -eq $subSetList.next_cursor)

# 4. Look up the correct Site GUID and save it to the connector configuration.
$siteList | Select-Object -Property name, uuid | Format-Table
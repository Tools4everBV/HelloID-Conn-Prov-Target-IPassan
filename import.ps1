#################################################
# HelloID-Conn-Prov-Target-IPassan-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-IPassanError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            } elseif ($errorDetailsObject.Error.message) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.Error.message
            } else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        } catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($httpErrorObj.ErrorDetails)] [$($_.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}

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
#endregion

try {
    Write-Information 'Starting IPassan account entitlement import'

    # Get Auth Token and set headers
    $token = Get-AuthToken
    $headers = @{
        Authorization = "Bearer $token"
    }

    $limit = 50
    $offset = 0
    $importedAccounts = [System.Collections.Generic.List[object]]::new()
    do {
        $splatImportAccountParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v1/access/site/$($actionContext.Configuration.siteId)/person?limit=$limit&offset=$offset"
            Method  = 'GET'
            Headers = $headers
        }
        $subSetAccountList = Invoke-RestMethod @splatImportAccountParams
        if ($null -ne $subSetAccountList.data) {
            $importedAccounts.AddRange($subSetAccountList.data)
        }
        $offset = $subSetAccountList.next_cursor
    }until ($null -eq $subSetAccountList.next_cursor)


    foreach ($importedAccount in $importedAccounts) {
        # Making sure only fieldMapping fields are imported
        $data = @{}
        foreach ($field in $actionContext.ImportFields | Where-Object { $_ -notmatch '_extension' }) {
            $data[$field] = $importedAccount.$field
        }

        # Set Enabled based on importedAccount status
        $isEnabled = $false
        if ( $null -ne $importedAccount.accessType.doorPermanent) {
            $isEnabled = $true
        }

        # Make sure the displayName has a value
        $displayName = "$($importedAccount.firstname) $($importedAccount.lastname)".trim()
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = $importedAccount.uuid
        }

        # Make sure the mail has a value
        if ([string]::IsNullOrWhiteSpace($importedAccount.mail)) {
            $importedAccount.mail = $importedAccount.uuid
        }

        # Return the result
        Write-Output @{
            AccountReference = $importedAccount.uuid
            displayName      = $displayName
            UserName         = $importedAccount.mail
            Enabled          = $isEnabled
            Data             = $data
        }
    }
    Write-Information 'IPassan account entitlement import completed'
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IPassanError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import IPassan account entitlements. Error: $($errorObj.FriendlyMessage)"
    } else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import IPassan account entitlements. Error: $($ex.Exception.Message)"
    }
}
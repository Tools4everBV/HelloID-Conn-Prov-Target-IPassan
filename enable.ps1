#################################################
# HelloID-Conn-Prov-Target-IPassan-Enable
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

# Script Configuration
# This table maps the _extension.accessProfileLookupKey property from the HelloID contract to the corresponding accessProfile in IPassan.
$mappingTableAccessProfile = @(
    @{
        HelloIDLookupKey  = 'Tester'
        AccessProfileName = 'Floor.1'
        AccessProfileId   = '51ee893c-bb6e-4a65-b852-f79d09e242b1'
    },
    @{
        HelloIDLookupKey  = 'ADMIN'
        AccessProfileName = 'ALL'
        AccessProfileId   = '759e0521-32a2-43d2-b0d7-585001743b64'
    },
    @{
        HelloIDLookupKey  = 'SUPPORT'
        AccessProfileName = 'Floor.2'
        AccessProfileId   = '8b32bb39-5e9f-459b-8bf1-a864c35b3f79'
    },
    @{
        HelloIDLookupKey  = 'SALES'
        AccessProfileName = 'Floor.2'
        AccessProfileId   = '8b32bb39-5e9f-459b-8bf1-a864c35b3f79'
    }
)

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Get Auth Token and set headers
    $token = Get-AuthToken
    $headers = @{
        Authorization = "Bearer $token"
    }

    Write-Information 'Verifying if a IPassan account exists'
    $splatGetPersonParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/api/v1/access/site/$($actionContext.Configuration.siteId)/person/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = $headers
    }
    $correlatedAccount = $null
    $responseGetPerson = Invoke-RestMethod @splatGetPersonParams
    if ($responseGetPerson.uuid) {
        $correlatedAccount = $responseGetPerson
    }

    if ($null -ne $correlatedAccount) {
        $action = 'EnableAccount'

        # Determine accessProfile with mapping
        if ($actionContext.Data._extension.accessProfileLookupKey) {
            $accessTypeDoorQuid = $mappingTableAccessProfile | Where-Object { $_.HelloIDLookupKey -eq $actionContext.Data._extension.accessProfileLookupKey }
        }

        if ($null -eq $accessTypeDoorQuid) {
            throw "The access type door GUID could not be mapped, with value: [$($actionContext.Data._extension.accessProfileLookupKey)]"
        }


    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'EnableAccount' {
            $bodyXWwwFrom = "accessType[doorPermanent]=$($accessTypeDoorQuid.AccessProfileId)"
            $splatEnableParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/v1/access/site/$($actionContext.Configuration.siteId)/person/$($actionContext.References.Account)"
                Method      = 'PUT'
                Body        = $bodyXWwwFrom
                Headers     = $headers
                ContentType = 'application/x-www-form-urlencoded'
            }
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Enabling IPassan account with accountReference: [$($actionContext.References.Account)] with AccessProfile: [$($accessTypeDoorQuid.accessProfileName)]"
                $null = Invoke-RestMethod @splatEnableParams

            } else {
                Write-Information "[DryRun] Enable IPassan account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }
            $outputContext.Data._extension.accessProfileLookupKey = $($accessTypeDoorQuid.AccessProfileId)
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Enable account with AccessProfile: [$($accessTypeDoorQuid.accessProfileName)] was successful"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "IPassan account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "IPassan account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }

} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IPassanError -ErrorObject $ex
        $auditMessage = "Could not enable IPassan account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not enable IPassan account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
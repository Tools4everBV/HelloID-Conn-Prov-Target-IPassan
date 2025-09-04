#################################################
# HelloID-Conn-Prov-Target-IPassan-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
        $correlatedAccount.type = "$($correlatedAccount.type)"
    }
    $outputContext.PreviousData = $correlatedAccount | Select-Object @(($actionContext.Data | Select-Object * -ExcludeProperty _extension, architecture ).PSObject.Properties.Name)
    $outputContext.PreviousData | Add-Member @{
        _extension = [PSCustomObject]@{
            accessProfileLookupKey = $correlatedAccount.accessType.doorPermanent
        }
    } -Force


    if ($null -ne $correlatedAccount) {
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @(($actionContext.Data | Select-Object * -ExcludeProperty _extension).PSObject.Properties)
        }
        $propertiesChangedPSNoteProperty = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        $propertiesChanged = @{}
        $propertiesChangedPSNoteProperty | ForEach-Object { $propertiesChanged[$_.Name] = $_.Value }

        # Only validate or update the accessType doorPermanent if it already exists.
        # This prevents unintentionally enabling a account during the update, as having an accessType means the account is considered "Enabled".
        if ($null -ne $correlatedAccount.accessType.doorPermanent) {
            # Determine accessProfile with mapping
            if ($actionContext.Data._extension.accessProfileLookupKey) {
                $accessTypeDoorQuid = $mappingTableAccessProfile | Where-Object { $_.HelloIDLookupKey -eq $actionContext.Data._extension.accessProfileLookupKey }
            }
            if ($null -eq $accessTypeDoorQuid) {
                throw "The access type door GUID could not be mapped, with value: [$($actionContext.Data._extension.accessProfileLookupKey)]"
            }

            # Validate if AccessType is Changed.
            if ($correlatedAccount.accessType.doorPermanent -ne $accessTypeDoorQuid.AccessProfileId) {
                $propertiesChanged['accessType[doorPermanent]'] = $($accessTypeDoorQuid.AccessProfileId)
            }
            $outputContext.Data._extension.accessProfileLookupKey = $accessTypeDoorQuid.AccessProfileId
        } else {
            $outputContext.Data._extension.accessProfileLookupKey = $null
        }

        if ($propertiesChanged.Count -gt 0) {
            $action = 'UpdateAccount'
        } else {
            $action = 'NoChanges'
        }
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Keys -join ', ')"
            $bodyXWwwFrom = ($propertiesChanged.GetEnumerator() | ForEach-Object { "$($_.name)=$($_.value)" }) -join '&'
            $splatUpdateParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/v1/access/site/$($actionContext.Configuration.siteId)/person/$($actionContext.References.Account)"
                Method      = 'PUT'
                Body        = $bodyXWwwFrom
                Headers     = $headers
                ContentType = 'application/x-www-form-urlencoded'
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating IPassan account with accountReference: [$($actionContext.References.Account)]"
                $null = Invoke-RestMethod @splatUpdateParams

            } else {
                Write-Information "[DryRun] Update IPassan account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            if ($propertiesChanged.Keys -contains 'accessType[doorPermanent]') {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Updating IPassan account with new AccessProfile: [$($accessTypeDoorQuid.AccessProfileName)]"
                        IsError = $false
                    })
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.Keys -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to IPassan account with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
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
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IPassanError -ErrorObject $ex
        $auditMessage = "Could not update IPassan account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update IPassan account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
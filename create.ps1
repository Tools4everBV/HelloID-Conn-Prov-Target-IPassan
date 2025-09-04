#################################################
# HelloID-Conn-Prov-Target-IPassan-Create
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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Get Auth Token and set headers
    $token = Get-AuthToken
    $headers = @{
        Authorization = "Bearer $token"
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        $limit = 50
        $offset = 0
        $accounts = [System.Collections.Generic.List[object]]::new()
        do {
            $splatImportAccountParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/v1/access/site/$($actionContext.Configuration.siteId)/person?limit=$limit&offset=$offset"
                Method  = 'GET'
                Headers = $headers
            }
            $subSetAccountList = Invoke-RestMethod @splatImportAccountParams
            if ($null -ne $subSetAccountList.data) {
                $accounts.AddRange($subSetAccountList.data)
            }
            $offset = $subSetAccountList.next_cursor
        }until ($null -eq $subSetAccountList.next_cursor)

        $correlatedAccount = $accounts | Where-Object { $_.$correlationField -eq $correlationValue }
    }

    if ($correlatedAccount.count -eq 0) {
        $action = 'CreateAccount'
    } elseif ($correlatedAccount.Count -eq 1) {
        $action = 'CorrelateAccount'
    } elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }

    Write-Information "Action to perform: [$action]"
    # Process
    switch ($action) {
        'CreateAccount' {
            $bodyXWwwFrom = ($actionContext.Data.PSObject.Properties | ForEach-Object { "$($_.name)=$($_.value)" }) -join '&'
            $splatCreateParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/v1/access/site/$($actionContext.Configuration.siteId)/person"
                Method      = 'POST'
                Body        = $bodyXWwwFrom
                Headers     = $headers
                ContentType = 'application/x-www-form-urlencoded'
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating IPassan account'
                $createdAccount = Invoke-RestMethod @splatCreateParams
                $outputContext.Data = $createdAccount | Select-Object * -ExcludeProperty architecture
                $outputContext.AccountReference = $createdAccount.Uuid
            } else {
                Write-Information '[DryRun] Create and correlate IPassan account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating IPassan account'
            $outputContext.Data = $correlatedAccount | Select-Object * -ExcludeProperty architecture
            $outputContext.AccountReference = $correlatedAccount.Uuid
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.Success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IPassanError -ErrorObject $ex
        $auditMessage = "Could not create or correlate IPassan account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate IPassan account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
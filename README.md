# HelloID-Conn-Prov-Target-IPassan

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-IPassan](#helloid-conn-prov-target-ipassan)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported  features](#supported--features)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Get All Users Correlation](#get-all-users-correlation)
    - [Site ID](#site-id)
    - [Enable / Disable](#enable--disable)
      - [AccessProfiles](#accessprofiles)
    - [Mapping](#mapping)
      - [Script mapping](#script-mapping)
      - [CSV Mapping](#csv-mapping)
      - [`_extension.accessProfileLookupKey`](#_extensionaccessprofilelookupkey)
    - [Unicode](#unicode)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-IPassan_ is a _target_ connector. _IPassan_ provides a set of REST API's that allow you to programmatically interact with its data.

## Supported  features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks                                          |
| ----------------------------------------- | --------- | --------------------------------------- | ------------------------------------------------ |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |                                                  |
| **Permissions**                           | ❌         | -                                       |                                                  |
| **Resources**                             | ❌         | -                                       |                                                  |
| **Entitlement Import: Accounts**          | ✅         | -                                       |                                                  |
| **Entitlement Import: Permissions**       | ❌         | -                                       | Permission are managed in the account lifeCycle. |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |                                                  |

## Getting started

### Prerequisites

- **AccessProfile Mapping**:<br>
A mapping between a HR property and the IPassan accessProfile. *(Read more: [Mapping](#mapping))*

- **SiteGuid**:<br>
A specific site Guid. *(Read more: [Site ID](#site-id))*

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                             | Mandatory |
| ------------ | --------------------------------------- | --------- |
| ClientId     | The ClientId to connect to the API      | Yes       |
| ClientSecret | The ClientSecret to connect to the API  | Yes       |
| BaseUrl      | The URL to the API                      | Yes       |
| SiteGuid     | The SiteGuid of the customer of the API | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _IPassan_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `number`                          |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the `Uuid` property from _IPassan_

## Remarks
### Get All Users Correlation
The API does not support filtering or retrieving individual accounts by EmployeeNumber. As a result, the connector always retrieves all accounts and filters the results within the connector. This can lead to performance issues or long request times when dealing with a large employee base. In such cases, you might consider using a resources script in combination with an external datasource (such as CSV file) to temporarily store the accounts, which can then serve as a staging table for correlation lookups.

### Site ID
- **Single Site**: The API requests are performed on a specific Site GUID, although a customer can theoretically have multiple sites, the connector only manages accounts on a specific site, the GUID of which can be entered.
- **Lookup Site GUID**: To look up the Site GUID, you can find an example script in the assets folder that shows how to find the correct Site GUID. <br>`Get-IPassanSiteGuid.ps1`
- **Access Denied**: An incorrect SiteId results in a `Access Denied` Error.

### Enable / Disable
- **Process**: Enabling or disabling an account can be done by adding or removing an AccessProfile, as having an accessType means the account is considered "Enabled." Besides enabling or disabling, the AccessProfile of an account can also be changed. This process is performed in the update script. To prevent accidentally enabling an account in the update script, the AccessProfile is only updated when the current account already has an AccessProfile.
- **DoorPermanent**: The AccessType doorPermanent is used to grant the accessProfiles.
- **Manual removed accessProfile**: Manually removed AccessProfile cannot be automatically restored by HelloID because the connector prevents adding AccessProfiles during the update action for accounts that don’t already have one. However, you can trigger a new enable action through reconciliation.
- **Import Script**: The import script checks whether or not an account does have AccessProfile.doorPermanent and returns the account as enabled if it does.

#### AccessProfiles
There are multiple AccessProfiles, but a single profile can be assigned to an account. While there are several ways to assign an AccessProfile.
The connector only manages assignmentType `doorPermanent`, which is used to grant, revoke and determine Accounts Access. The other assignmentType are out of scope for the connector. *(Possible types: doorPermanent, doorTemporary, floorPermanent, floorTemporary)*

### Mapping
Because it is only possible to add a single `permissions` to an account, the `permissions` *(AccessProfiles)* are managed in the account lifecycle. Therefore, additional mapping is required.

#### Script mapping
The `Enable.ps1` and `Update.ps1` contain a script mapping table. To map a HelloID property to a IPassan AccessProfile. Based on the value in the field `_extension.accessProfileLookupKey`.

#### CSV Mapping
For the case that the (Build in mapping) does not meet the customer requirements, there is a Example csv mapping listed in the assets folder. Use the following `Import-Csv` Cmdlet to import the mapping in to the connector.



```PowerShell
$mappingTableAccessProfile = Import-Csv '<Path to Mapping File>\AccessProfile.csv' -Delimiter ';'
```

> [!IMPORTANT]
> Mapping is required for the `Enable` and `Update` script.

#### `_extension.accessProfileLookupKey`
The value of fieldMapping field is used in the mapping file to determine which accessProfile must be granted.

> [!IMPORTANT]
> When the GUID provided in the mapping does not actually exist in IPassan, the assignment will be ignored without warning, which results in the account not being granted access.

### Unicode
The connector is designed for the Cloud agent; however, if you want to use a local CSV file for mapping, it requires using an On-premises agent with PowerShell 5.1. Incorrect encoding may cause incorrect diacritics. This can be resolved by formatting the $correlatedAccount with the following line. This is important for the Update and Compare action.
```Powershell
$correlatedAccount = [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(28591).GetBytes(($correlatedAccount | ConvertTo-Json))) | ConvertFrom-Json
```
## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                                          | Description                     |
| ------------------------------------------------- | ------------------------------- |
| /api/v1/token                                     | Retrieve Bearer Token           |
| /api/v1/access/site/:SiteGuid/person              | CURD Person/Account information |
| /api/v1/access/site/:SiteGuid/person/:AccountGuid | CURD Person/Account information |

### API documentation

Swagger: [Swagger](https://ipassan.com/swagger)

IPassanManager: [IPassanManager](https://www.ipassan.com/public/files/fdi/help/IPassan%20Manager.pdf)

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/5377-helloid-conn-prov-target-ipassan)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

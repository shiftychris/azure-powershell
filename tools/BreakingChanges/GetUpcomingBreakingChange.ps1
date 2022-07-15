# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

# To get upcoming breaking change info, you need to build the debug version of az first
# ```powershell
# dotnet msbuild build.proj /t:build /p:configuration=debug
# Import-Module tools/BreakingChanges/GetUpcomingBreakingChange.ps1
# Export-BreakingChangeMsg, this will create `UpcommingBreakingChanges.md` under current path
# ```

# Get-BreakingChangeInfoOfModule -ArtifactsPath ..\azure-powershell\artifacts\Debug\ -ModuleName Az.Resources | ConvertTo-Json -Depth 4 | Out-File a.json
Function Get-AttributeSpecificMessage
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [System.Object]
        $attribute
    )
    If ($Null -ne $attribute.ChangeDescription)
    {
        Return $attribute.ChangeDescription
    }
    # GenericBreakingChangeAttribute is the base class of the BreakingChangeAttribute classes and have a protected method named as Get-AttributeSpecIficMessage.
    # We can use this to get the specIfic message to show on document.
    $Method = $attribute.GetType().GetMethod('GetAttributeSpecificMessage', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)

    Return $Method.Invoke($attribute, @()).Trim()
}

# Get the breaking change info of the cmdlet Parameter.
Function Find-ParameterBreakingChange
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [System.Management.Automation.ParameterMetadata]
        $ParameterInfo
    )

    ForEach ($attribute In $ParameterInfo.Attributes)
    {
        If ($attribute.TypeId.BaseType.Name -eq 'GenericBreakingChangeAttribute')
        {
            Return Get-AttributeSpecIficMessage($attribute)
        }
    }

    Return $Null
}

# Get the breaking change info of the cmdlet.
Function Find-CmdletBreakingChange
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [System.Management.Automation.CommandInfo]
        $CmdletInfo
    )
    $Result = @{}
    #Region get breaking change info of cmdlet
    $customAttributes = $CmdletInfo.ImplementingType.GetTypeInfo().GetCustomAttributes([System.object], $true)
    ForEach ($customAttribute In $customAttributes)
    {
        If ($customAttribute.TypeId.BaseType.Name -eq 'GenericBreakingChangeAttribute')
        {
            $tmp = Get-AttributeSpecIficMessage($customAttribute)
            If (-not $Result.ContainsKey("AllParameterSets"))
            {
                $Null = $Result.Add("AllParameterSets", @{
                    CmdletBreakingChange = @($tmp)
                })
            }
            ElseIf (-not $Result['AllParameterSets'].ContainsKey("CmdletBreakingChange"))
            {
                $Result['AllParameterSets']["CmdletBreakingChange"] = @($tmp)
            }
            Else
            {
                $Result['AllParameterSets']["CmdletBreakingChange"] += @($tmp)
            }
        }
    }
    #EndRegion

    #Region get breaking change info of parameters
    $ParameterBreakingChanges = @{}
    ForEach ($ParameterInfo In $CmdletInfo.Parameters.values)
    {
        $ParameterBreakingChange = Find-ParameterBreakingChange($ParameterInfo)
        If ($Null -ne $ParameterBreakingChange)
        {
            $Null = $ParameterBreakingChanges.Add($ParameterInfo.Name, $ParameterBreakingChange)
        }
    }
    If ($ParameterBreakingChanges.Count -ne 0)
    {
        If (-not $Result.ContainsKey("AllParameterSets"))
        {
            $Null = $Result.Add("AllParameterSets", @{
                ParameterBreakingChange = $ParameterBreakingChanges
            })
        }
        Else
        {
            $Result["AllParameterSets"].Add("ParameterBreakingChange", $ParameterBreakingChanges)
        }
    }
    #EndRegion

    Return $Result
}

# Get the upcoming breaking change document of the module.
Function Get-ModuleBreakingChangeMsg
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [String]
        $ModuleName
    )
    #Region get the breaking changes of cmdlets and parameters
    $psd1Path = [System.IO.Path]::Combine($PSScriptRoot, "..", "..", "artifacts", "Debug", "$ModuleName", "$ModuleName.psd1")
    Import-Module $psd1Path
    $ModuleInfo = Get-Module $ModuleName
    $Result = @{}
    ForEach ($cmdletInfo In $ModuleInfo.ExportedCmdlets.Values)
    {
        $cmdletBreakingChangeInfo = Find-CmdletBreakingChange($cmdletInfo)
        If ($cmdletBreakingChangeInfo.Count -ne 0)
        {
            $Result.Add($cmdletInfo.Name, $cmdletBreakingChangeInfo)
        }
    }
    #EndRegion

    #Region combine the breaking change messages into markdown format
    If ($Result.Count -ne 0)
    {
        $Msg = "# $ModuleName`n"
        ForEach ($cmdletName In $Result.Keys)
        {
            $Msg += "`n## $cmdletName`n"
            $cmdletBreakingChangeInfo = $Result[$cmdletName]
            ForEach ($key In $cmdletBreakingChangeInfo.Keys)
            {
                If ($key -ne 'Parameter')
                {
                    $Msg += $cmdletBreakingChangeInfo[$key]
                }
                Else
                {
                    ForEach ($parameterName In $cmdletBreakingChangeInfo['Parameter'].Keys)
                    {
                        $Msg += "### $ParameterName`n"
                        $Msg += ($cmdletBreakingChangeInfo['Parameter'][$ParameterName] + "`n")
                    }
                }
            }
        }
        Return $Msg
    }
    #EndRegion
}

Function Export-BreakingChangeMsg
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [String]
        $ArtifactsPath
    )
    $moduleList = (Get-ChildItem -Path $ArtifactsPath).Name
    $totalResult = ''
    ForEach ($moduleName In $moduleList)
    {
        $msg = Get-ModuleBreakingChangeMsg($moduleName)
        If ($Null -ne $msg)
        {
            $totalResult += "`n`n$msg"
        }
    }

    $totalResult | Out-File -LiteralPath "UpcommingBreakingChanges.md"
}

Function Get-BreakingChangeInfoOfModule
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [String]
        $ArtifactsPath,
        [Parameter()]
        [String]
        $ModuleName
    )
    $BreakingChangeMessages = @{}
    $ModuleRoot = [System.IO.Path]::Combine($ArtifactsPath, "$ModuleName")

    #Region Generated modules
    $Dlls = Get-ChildItem -Path $ModuleRoot -Filter *.private.dll -Recurse
    ForEach ($Dll In $Dlls)
    {
        $CustomRoot = [System.IO.Path]::Combine($Dll, '..', '..', 'custom')
        $Psm1Path = Get-ChildItem -Path $CustomRoot -Filter *.psm1
        $BreakingChangeMessage = Get-BreakingChangeOfGeneratedModule -DllPath $Dll -Psm1Path $Psm1Path
        $BreakingChangeMessages += $BreakingChangeMessage
    }
    #EndRegion

    #Region SDK based modules
    $psd1Path = [System.IO.Path]::Combine($ModuleRoot, "$ModuleName.psd1")
    Import-Module $psd1Path
    $ModuleInfo = Get-Module $ModuleName
    ForEach ($cmdletInfo In $ModuleInfo.ExportedCmdlets.Values)
    {
        $cmdletBreakingChangeInfo = Find-CmdletBreakingChange($cmdletInfo)
        If ($cmdletBreakingChangeInfo.Count -ne 0)
        {
            $BreakingChangeMessages.Add($cmdletInfo.Name, $cmdletBreakingChangeInfo)
        }
    }
    #EndRegion

    Return $BreakingChangeMessages
}

Function Get-BreakingChangeMessageFromGeneratedAttribute
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [Object]
        $Attribute,
        [Parameter()]
        [Object]
        $AttributeType
    )
    $StringBuilder = [System.Text.StringBuilder]::New()

    # $GetAttributeSpecificMessageMethod = $AttributeType.GetMethod('GetAttributeSpecificMessage', [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
    # $BreakingChangeMessage = $GetAttributeSpecificMessageMethod.Invoke($Attribute, @())
    # $Null = $StringBuilder.Append($BreakingChangeMessage)

    $PrintCustomAttributeInfo = [System.Action[System.String]]{
        Param([System.String] $s)
        $StringBuilder.Append($s)
    }
    $PrintCustomAttributeInfoMethod = $AttributeType.GetMethod('PrintCustomAttributeInfo', [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance)
    $Null = $PrintCustomAttributeInfoMethod.Invoke($Attribute, @($PrintCustomAttributeInfo))

    Return $StringBuilder.ToString().Trim()
}

Function Get-BreakingChangeOfGeneratedModule
{
    [CmdletBinding()]
    Param (
        [Parameter()]
        [String]
        $DllPath,
        [Parameter()]
        [String]
        $Psm1Path
    )
    $AllBreakingChangeMessages = @{}

    #Region Dll
    $Dll = [Reflection.Assembly]::LoadFrom($DllPath)
    $Cmdlets = $Dll.ExportedTypes | Where-Object { $_.CustomAttributes.Attributetype.name -contains "GeneratedAttribute" }

    $BreakingChangeCmdlets = $Cmdlets | Where-Object { $_.CustomAttributes.Attributetype.BaseType.Name -contains "GenericBreakingChangeAttribute" }
    ForEach ($BreakingChangeCmdlet in $BreakingChangeCmdlets)
    {
        $ParameterSetName = $BreakingChangeCmdlet.Name
        $CmdletAttribute = $BreakingChangeCmdlet.CustomAttributes | Where-Object { $_.AttributeType.Name -eq 'CmdletAttribute' }
        $Verb = $CmdletAttribute.ConstructorArguments[0].Value
        $Noun = $CmdletAttribute.ConstructorArguments[1].Value.Split('_')[0]
        $CmdletName = "$Verb-$Noun"

        $BreakingChangeAttributes = $BreakingChangeCmdlet.CustomAttributes | Where-Object { $_.Attributetype.BaseType.Name -eq 'GenericBreakingChangeAttribute' }
        ForEach ($BreakingChangeAttribute In $BreakingChangeAttributes)
        {
            $Attribute = $BreakingChangeAttribute.Constructor.Invoke(@($BreakingChangeAttribute.ConstructorArguments.value))
            $BreakingChangeMessage = Get-BreakingChangeMessageFromGeneratedAttribute -Attribute $Attribute -AttributeType $Attribute.GetType()
    
            If (-not $AllBreakingChangeMessages.ContainsKey($CmdletName))
            {
                $AllBreakingChangeMessages.Add($CmdletName, @{})
            }
            If (-not $AllBreakingChangeMessages[$CmdletName].ContainsKey($ParameterSetName))
            {
                $AllBreakingChangeMessages[$CmdletName].Add($ParameterSetName, @{
                    "CmdletBreakingChange" = @($BreakingChangeMessage)
                })
            }
            Else {
                $AllBreakingChangeMessages[$CmdletName][$ParameterSetName] += @(BreakingChangeMessage)
            }
        }
    }

    ForEach ($Cmdlet in $Cmdlets)
    {
        $ParameterBreakingChangeMessage = @{}
        $ParameterSetName = $Cmdlet.Name
        $CmdletAttribute = $Cmdlet.CustomAttributes | Where-Object { $_.AttributeType.Name -eq 'CmdletAttribute' }
        $Verb = $CmdletAttribute.ConstructorArguments[0].Value
        $Noun = $CmdletAttribute.ConstructorArguments[1].Value.Split('_')[0]
        $CmdletName = "$Verb-$Noun"

        $Parameters = $Cmdlet.DeclaredMembers | Where-Object { $_.CustomAttributes.Attributetype.BaseType.Name -eq 'GenericBreakingChangeAttribute' }
        ForEach ($Parameter In $Parameters)
        {
            $ParameterName = $Parameter.Name
            $ParameterAttribute = $Parameter.CustomAttributes | Where-Object { $_.AttributeType.BaseType.Name -eq 'GenericBreakingChangeAttribute' }
            $Attribute = $ParameterAttribute.Constructor.Invoke(@($ParameterAttribute.ConstructorArguments.value))
            $BreakingChangeMessage = Get-BreakingChangeMessageFromGeneratedAttribute -Attribute $Attribute -AttributeType $Attribute.GetType()
            $ParameterBreakingChangeMessage.Add($ParameterName, $BreakingChangeMessage)
        }
        If ($ParameterBreakingChangeMessage.Count -ne 0)
        {
            If (-not $AllBreakingChangeMessages.ContainsKey($CmdletName))
            {
                $AllBreakingChangeMessages.Add($CmdletName, @{})
            }
            If (-not $AllBreakingChangeMessages[$CmdletName].ContainsKey($ParameterSetName))
            {
                $AllBreakingChangeMessages[$CmdletName].Add($ParameterSetName, @{
                    "ParameterBreakingChange" = $ParameterBreakingChangeMessage
                })
            }
            Else {
                $AllBreakingChangeMessages[$CmdletName][$ParameterSetName].Add('ParameterBreakingChange', $ParameterBreakingChangeMessage)
            }
        }
    }
    #EndRegion

    #Region psm1
    Import-Module $Psm1Path -Force
    $ModuleName = (Get-Item $Psm1Path).BaseName
    $ModuleInfo = Get-Module $ModuleName
    $BreakingChangeCmdlets = $ModuleInfo.ExportedCommands.Values | Where-Object { $_.ScriptBlock.Attributes.TypeId.BaseType.Name -contains 'GenericBreakingChangeAttribute' }
    ForEach ($BreakingChangeCmdlet In $BreakingChangeCmdlets)
    {
        $CmdletName = $BreakingChangeCmdlet.Name
        $BreakingChangeAttributes = $BreakingChangeCmdlet.ScriptBlock.Attributes | Where-Object { $_.TypeId.BaseType.Name -eq 'GenericBreakingChangeAttribute' }
        ForEach ($BreakingChangeAttribute In $BreakingChangeAttributes)
        {
            $BreakingChangeMessage = Get-BreakingChangeMessageFromGeneratedAttribute -Attribute $BreakingChangeAttribute -AttributeType $BreakingChangeAttribute.TypeId
            If (-not $AllBreakingChangeMessages.ContainsKey($CmdletName))
            {
                $AllBreakingChangeMessages.Add($CmdletName, @{})
            }
            If (-not $AllBreakingChangeMessages[$CmdletName].ContainsKey("AllParameterSets"))
            {
                $AllBreakingChangeMessages[$CmdletName].Add("AllParameterSets", @{
                    "CmdletBreakingChange" = @($BreakingChangeMessage)
                })
            }
            Else {
                $AllBreakingChangeMessages[$CmdletName]["AllParameterSets"] += @($BreakingChangeMessage)
            }
        }
    }

    $Cmdlets = $ModuleInfo.ExportedCommands.Values
    ForEach ($Cmdlet In $Cmdlets)
    {
        $CmdletName = $Cmdlet.Name
        $ParameterBreakingChangeMessage = @{}
        $Parameters = $Cmdlet.Parameters.Values | Where-Object { $_.Attributes.TypeId.BaseType.Name -eq 'GenericBreakingChangeAttribute' }
        ForEach ($Parameter In $Parameters)
        {
            $ParameterName = $Parameter.Name
            $ParameterAttribute = $Parameter.Attributes | Where-Object { $_.TypeId.BaseType.Name -eq 'GenericBreakingChangeAttribute' }
            $BreakingChangeMessage = Get-BreakingChangeMessageFromGeneratedAttribute -Attribute $ParameterAttribute -AttributeType $ParameterAttribute.TypeId
            $ParameterBreakingChangeMessage.Add($ParameterName, $BreakingChangeMessage)
        }
        If ($ParameterBreakingChangeMessage.Count -ne 0)
        {
            If (-not $AllBreakingChangeMessages.ContainsKey($CmdletName))
            {
                $AllBreakingChangeMessages.Add($CmdletName, @{})
            }
            If (-not $AllBreakingChangeMessages[$CmdletName].ContainsKey("AllParameterSets"))
            {
                $AllBreakingChangeMessages[$CmdletName].Add("AllParameterSets", @{
                    "ParameterBreakingChange" = $ParameterBreakingChangeMessage
                })
            }
            Else {
                $AllBreakingChangeMessages[$CmdletName]["AllParameterSets"].Add('ParameterBreakingChange', $ParameterBreakingChangeMessage)
            }
        }
    }
    #EndRegion

    Return $AllBreakingChangeMessages
}
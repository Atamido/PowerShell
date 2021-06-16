Function Get-Window {
    [OutputType([PSCustomObject])]
    Param(
        [Parameter(ParameterSetName = 'Default', Mandatory = $false)]
        [Parameter(ParameterSetName = 'Process', Mandatory = $false)]
        [String]
        $WindowTitle,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false)]
        [Parameter(ParameterSetName = 'Process', Mandatory = $false)]
        [String]
        $WindowClass,

        [Parameter(ParameterSetName = 'Process', Mandatory = $true, ValueFromPipeline = $true)]
        [System.Diagnostics.Process[]]
        $InputObject,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false)]
        [Switch]
        $IncludeProcess,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false)]
        [Parameter(ParameterSetName = 'Process', Mandatory = $false)]
        [Switch]
        $IncludeHidden,

        [Parameter(ParameterSetName = 'Default', Mandatory = $false)]
        [Parameter(ParameterSetName = 'Process', Mandatory = $false)]
        [Int[]]
        $WindowHandle = @()
    )

    Begin {
        #  Get-DelegateType is taken from https://github.com/PowerShellMafia
        #  Used to dynamically create a delegate function that is required by some defined Win32 methods (like User32 EnumWindows)
        function Local:Get-DelegateType {
            Param
            (
                [OutputType([Type])]
                [Parameter( Position = 0)][Type[]]$Parameters = (New-Object Type[](0)),
                [Parameter( Position = 1 )][Type]$ReturnType = [Void]
            )

            $Domain = [AppDomain]::CurrentDomain
            $DynAssembly = New-Object System.Reflection.AssemblyName('ReflectedDelegate')
            $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
            $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
            $TypeBuilder = $ModuleBuilder.DefineType('MyDelegateType', 'Class, Public, Sealed, AnsiClass, AutoClass', [System.MulticastDelegate])
            $ConstructorBuilder = $TypeBuilder.DefineConstructor('RTSpecialName, HideBySig, Public', [System.Reflection.CallingConventions]::Standard, $Parameters)
            $ConstructorBuilder.SetImplementationFlags('Runtime, Managed')
            $MethodBuilder = $TypeBuilder.DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $ReturnType, $Parameters)
            $MethodBuilder.SetImplementationFlags('Runtime, Managed')

            Write-Output $TypeBuilder.CreateType()
        }


        #  Much of the code for using user32.dll and Microsoft.Win32.NativeMethods was taken from
        #  http://www.exploit-monday.com/2013/06/PowerShellCallbackFunctions.html
        #  Define p/invoke method for User32!EnumWindows
        $DynAssembly = New-Object System.Reflection.AssemblyName('SysUtils')
        $AssemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('SysUtils', $False)
        $TypeBuilder = $ModuleBuilder.DefineType('User32', 'Public, Class')

        #[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        #[return: MarshalAs(UnmanagedType.Bool)]
        #public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.Collections.ArrayList lParam);
        [String]$DllName = 'user32.dll'
        $PInvokeMethod = $TypeBuilder.DefinePInvokeMethod('EnumWindows',
            $DllName,
            [Reflection.MethodAttributes] 'Public, Static',
            [Reflection.CallingConventions]::Standard,
            #  Return type
            [Bool],
            # Argument types
            [Type[]] @([MulticastDelegate], [System.Collections.ArrayList]),
            [Runtime.InteropServices.CallingConvention]::Winapi,
            [Runtime.InteropServices.CharSet]::Auto )
        $PInvokeMethod.SetCustomAttribute((New-Object Reflection.Emit.CustomAttributeBuilder([Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String])), @($DllName))))

        #[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        #public static extern int GetClassName(IntPtr hWnd, string lpClassName, int nMaxCount);
        $PInvokeMethod = $TypeBuilder.DefinePInvokeMethod('GetClassName',
            $DllName,
            [Reflection.MethodAttributes] 'Public, Static',
            [Reflection.CallingConventions]::Standard,
            #  Return type
            [Int],
            #  Argument types
            [Type[]] @([IntPtr], [String], [Int]),
            [Runtime.InteropServices.CallingConvention]::Winapi,
            [Runtime.InteropServices.CharSet]::Auto )
        $PInvokeMethod.SetCustomAttribute((New-Object Reflection.Emit.CustomAttributeBuilder([Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String])), @($DllName))))

        <#
        #[DllImport(ExternDll.User32, CharSet=System.Runtime.InteropServices.CharSet.Auto, SetLastError=true)]
        #public static extern int GetWindowThreadProcessId(HandleRef handle, out int processId);
        $PInvokeMethod = $TypeBuilder.DefinePInvokeMethod('GetWindowThreadProcessId',
                                            $DllName,
                                            [Reflection.MethodAttributes] 'Public, Static',
                                            [Reflection.CallingConventions]::Standard,
                                            #  Return type
                                            [Int],
                                            #  Argument types
                                            [Type[]] @([IntPtr], [UInt32].MakeByRefType()),
                                            [Runtime.InteropServices.CallingConvention]::Winapi,
                                            [Runtime.InteropServices.CharSet]::Auto )
        $PInvokeMethod.SetCustomAttribute((New-Object Reflection.Emit.CustomAttributeBuilder([Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String])), @($DllName))))
        #>

        $User32 = $TypeBuilder.CreateType()

        #  Import ExternDll methods made available by .NET nativemethod.cs
        #  Available methods for import and definitions visible here:
        #  https://referencesource.microsoft.com/#system/compmod/microsoft/win32/nativemethods.cs
        $mscorlib = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.ManifestModule.Name -eq 'System.dll' }
        $NativeMethods = $mscorlib.GetType('Microsoft.Win32.NativeMethods')
        #  Expose methods as variables
        $GetWindowTextLength = $NativeMethods.GetMethod('GetWindowTextLength', ([Reflection.BindingFlags] 'Public, Static'))
        $GetWindowText = $NativeMethods.GetMethod('GetWindowText', ([Reflection.BindingFlags] 'Public, Static'))
        $GetWindowThreadProcessId = $NativeMethods.GetMethod('GetWindowThreadProcessId', ([Reflection.BindingFlags] 'Public, Static'))
        $IsWindowVisible = $NativeMethods.GetMethod('IsWindowVisible', ([Reflection.BindingFlags] 'Public, Static'))


        $P = @()
        $Processes = @{}
        if ($IncludeProcess) {
            $P = @(Get-Process)
        }
        $P | ForEach-Object { $Processes["$($_.Id)"] = $_ }

        Write-Verbose "There are $($Processes.Count) processes"


        # This scriptblock will serve as the callback function to get window handles
        $EnumWindowsProcAction = {
            # Define params in place of $args[0] and $args[1]
            # Note: These parameters need to match the params
            # of EnumChildProc.
            Param (
                [IntPtr] $hWnd,
                [System.Collections.ArrayList] $lParam
            )

            $null = $lParam.Add([Int]($hWnd))

            # Returning true will allow EnumWindows to continue iterating through each window
            return $true
        }
        #  Retrieve list of window handle pointers
        #  Create a delegate type with EnumWindowsProc function signature
        $EnumWindowsProcDelegateType = Get-DelegateType @([IntPtr], [System.Collections.ArrayList]) ([Bool])
        #  Cast the scriptblock as the just created delegate
        $EnumWindowsProcFunction = $EnumWindowsProcAction -as $EnumWindowsProcDelegateType
        [System.Collections.ArrayList]$hWnds = @()
        $null = $User32::EnumWindows($EnumWindowsProcFunction, $hWnds)
        if ($WindowHandle -and $WindowHandle.Count -gt 0) {
            $hWnds = @($hWnds | Where-Object { $_ -in $WindowHandle })
        }
        if ($hWnds.Count -eq 0) {
            return
        }

        Write-Verbose "There are $($hWnds.Count) window handles"

        #  Quick method to create a string of ~293 characters.  Longer titles will be truncated.
        [String]$tempClassName = [String]::new(' ', 256)
        [System.Collections.ArrayList]$Windows = @()


        #  Iterate through window handles and get information for each handle from user32.dll functions
        foreach ($hWnd in $hWnds) {
            try {
                [Int]$ClassNameLength = 0
                [String]$ClassName = $null
                [Int]$WindowTextLength = 0
                [String]$WindowText = $null
                [UInt32]$ThreadID = $null
                [Int32]$ProcID = $null
                [Bool]$Visible = $true
                $HandleRef = [Runtime.InteropServices.HandleRef]::new($this, $hWnd)

                $Visible = $IsWindowVisible.Invoke($null, @($HandleRef))
                if (!$Visible -and !$IncludeHidden) {
                    continue
                }

                $ClassNameLength = $User32::GetClassName($hWnd, $tempClassName, 256)
                $ClassName = $tempClassName.Substring(0, $ClassNameLength)
                $WindowTextLength = $GetWindowTextLength.Invoke($null, @($HandleRef))
                $WindowTextSB = [Text.StringBuilder]::new(($WindowTextLength + 1))
                $null = $GetWindowText.Invoke($null, @($HandleRef, $WindowTextSB, $WindowTextSB.Capacity))
                $WindowText = $WindowTextSB.ToString()
                #$ThreadID = $User32::GetWindowThreadProcessId($hWnd, [ref]$ProcID)
                $GWTIParam = @($HandleRef, $null)
                $ThreadID = $GetWindowThreadProcessId.Invoke($null, $GWTIParam)
                $ProcID = $GWTIParam[1]
            }
            catch {
                Write-Error $Error[0].Exception
            }

            if ($null -eq $ClassName -and $null -eq $WindowText -and $null -eq $ThreadID -and $null -eq $ProcID) {
                continue
            }

            $Window = New-Object -TypeName psobject -Property @{
                WindowHandle = $hWnd;
                WindowClass  = $ClassName;
                WindowTitle  = $WindowText;
                ThreadID     = $ThreadID;
                ProcessID    = $ProcID;
                Process      = $null;
                Visible      = $Visible
            }
            $null = $Windows.Add($Window)
        }

        Write-Verbose "There are $($Windows.Count) unfiltered window handles"

        $FilteredWindows = @($Windows | Where-Object { $true })

        if ($WindowClass) {
            $FilteredWindows = $FilteredWindows | Where-Object { $_.WindowClass -like $WindowClass }
        }
        if ($WindowTitle) {
            $FilteredWindows = $FilteredWindows | Where-Object { $_.WindowTitle -like $WindowTitle }
        }

        Write-Verbose "There are $($FilteredWindows.Count) filtered window handles"
    }

    Process {
        if ($InputObject) {
            $InputObject | ForEach-Object { $Processes["$($_.Id)"] = $_ }
        }
    }

    End {
        if ($Processes.Count -gt 0) {
            foreach ($Window in $FilteredWindows) {
                if ($Processes.ContainsKey("$($Window.ProcessID)")) {
                    $Window.Process = $Processes["$($Window.ProcessID)"]
                }
            }

            if (!$IncludeProcess) {
                $FilteredWindows = @($FilteredWindows | Where-Object { $null -ne $_.Process })
            }
        }

        $FilteredWindows | Write-Output
    }
}
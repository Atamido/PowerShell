Function Show-Window {
    Param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ParameterSetName='GetWindow')]
        [ValidateScript({[bool]($_ | Get-Member -Name 'WindowHandle')})]
        [PSCustomObject[]]
        $WindowObjects,

        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   ParameterSetName='Default')]
        [Int[]]
        $WindowHandle,

        [Parameter(Mandatory=$true,
                   ParameterSetName='Default')]
        [Parameter(Mandatory=$true,
                   ParameterSetName='GetWindow')]
        [ValidateSet('Hide', 'ShowNormal', 'ShowMinimized', 'ShowMaximized', 'ShowNoActivate', 'Show', 'Minimize', 'ShowMinNoActive', 'ShowNA', 'Restore', 'ShowDefault', 'ForceMinimize')]
        [String]
        $WindowAction
    )

    Begin {
        #  List of available values for WindowAction
        #  Default '0' is 'hide window'
        #  https://msdn.microsoft.com/en-us/library/windows/desktop/ms633548(v=vs.85).aspx
        [String[]]$nCmdShowString = @('Hide', 'ShowNormal', 'ShowMinimized', 'ShowMaximized', 'ShowNoActivate', 'Show', 'Minimize', 'ShowMinNoActive', 'ShowNA', 'Restore', 'ShowDefault', 'ForceMinimize')
        [Int]$nCmdShow = $nCmdShowString.IndexOf($WindowAction)


        #  Much of the code for using user32.dll and Microsoft.Win32.NativeMethods was taken from
        #  http://www.exploit-monday.com/2013/06/PowerShellCallbackFunctions.html
        #  Define p/invoke method for User32!EnumWindows
        $DynAssembly = New-Object System.Reflection.AssemblyName('SysUtils')
        $AssemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('SysUtils', $False)
        $TypeBuilder = $ModuleBuilder.DefineType('User32', 'Public, Class')

        #[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        #public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [String]$DllName = 'user32.dll'
        $PInvokeMethod = $TypeBuilder.DefinePInvokeMethod('ShowWindow',
                                            $DllName,
                                            [Reflection.MethodAttributes] 'Public, Static',
                                            [Reflection.CallingConventions]::Standard,
                                            #  Return type
                                            [Bool],
                                            # Argument types
                                            [Type[]] @([IntPtr], [Int]),
                                            [Runtime.InteropServices.CallingConvention]::Winapi,
                                            [Runtime.InteropServices.CharSet]::Auto )
        $PInvokeMethod.SetCustomAttribute((New-Object Reflection.Emit.CustomAttributeBuilder([Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String])), @($DllName))))

        $User32 = $TypeBuilder.CreateType()
    }

    Process {
        if ($WindowHandle.Count -gt 0) {
            foreach ($hWnd in $WindowHandle) {
                New-Object -TypeName psobject -Property @{
                            WindowHandle = $hWnd;
                            ShowWindowResult = $User32::ShowWindow($hWnd, $nCmdShow)
                        } | Write-Output
            }
        } else {
            foreach ($Window in $WindowObjects) {
                $hWnd = $Window.WindowHandle
                $Window | Add-Member -MemberType NoteProperty -Name ShowWindowResult -Value ($User32::ShowWindow($hWnd, $nCmdShow)) -PassThru | Write-Output
            }
        }
    }

    End {}
}
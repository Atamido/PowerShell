Function Set-Window {
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


        $MethodDefinition = @'
            [DllImport("user32.dll", SetLastError=true, CharSet = CharSet.Auto)]
            public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern int GetWindowText(IntPtr hWnd, string strText, int maxCount);

            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern int GetWindowTextLength(IntPtr hWnd);

            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            public static extern int GetClassName(IntPtr hWnd, string lpClassName, int nMaxCount);

            // Delegate to filter which windows to include.  Required by EnumWindows()
            public delegate bool EnumWindowsProc(IntPtr hwnd, System.Collections.ArrayList lParam);

            [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, System.Collections.ArrayList lParam);

            // These two functions are in C# because I can't figure out how to use the .NET API callback functionality via PowerShell
            public static System.Collections.ArrayList GetWindows()
            {
                System.Collections.ArrayList windowHandles = new System.Collections.ArrayList();
                EnumWindowsProc callBackPtr = GetWindowHandle;
                EnumWindows(callBackPtr, windowHandles);

                return windowHandles;
            }

            private static bool GetWindowHandle(IntPtr hwnd, System.Collections.ArrayList windowHandles)
            {
                windowHandles.Add(hwnd);
                return true;
            }
'@

        if (-not ([System.Management.Automation.PSTypeName]'User32.SetGetWindow').Type) {
            Add-Type -MemberDefinition $MethodDefinition -Name 'SetGetWindow' -Namespace 'User32' | Out-Null
        }
    }


    Process {
        if ($WindowHandle.Count -gt 0) {
            foreach ($hWnd in $WindowHandle) {
                New-Object -TypeName psobject -Property @{
                            WindowHandle = $hWnd;
                            Result = [User32.SetGetWindow]::ShowWindow($hWnd, $nCmdShow)
                        } | Write-Output
            }
        } else {
            foreach ($Window in $WindowObjects) {
                $hWnd = $Window.WindowHandle
                $Window | Add-Member -MemberType NoteProperty -Name Result -Value ([User32.SetGetWindow]::ShowWindow($hWnd, $nCmdShow)) -PassThru | Write-Output
            }
        }
    }

    End {}
}
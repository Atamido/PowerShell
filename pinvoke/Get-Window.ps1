Function Get-Window {
    Param(
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'ProcessName')]
        [Parameter(ParameterSetName = 'ProcessID')]
        [String]
        $WindowTitle,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'ProcessName')]
        [Parameter(ParameterSetName = 'ProcessID')]
        [String]
        $WindowClass,

        [Parameter(ParameterSetName = 'ProcessName')]
        [String[]]
        $ProcessName,

        [Parameter(ParameterSetName = 'ProcessID')]
        [Int[]]
        $ProcessID,

        [Parameter(ParameterSetName = 'Default')]
        [Switch]
        $IncludeProcess,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'ProcessName')]
        [Parameter(ParameterSetName = 'ProcessID')]
        [Int[]]
        $WindowHandles = @()
    )

    #  List of available values for WindowAction
    #  Default '0' is 'hide window'
    #  https://msdn.microsoft.com/en-us/library/windows/desktop/ms633548(v=vs.85).aspx
    #[String[]]$nCmdShow = @('Hide', 'ShowNormal', 'ShowMinimized', 'ShowMaximized', 'ShowNoActivate', 'Show', 'Minimize', 'ShowMinNoActive', 'ShowNA', 'Restore', 'ShowDefault', 'ForceMinimize')



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

    $Processes = @{}
    if (!([String]::IsNullOrEmpty($ProcessName))) {
        $P = @(Get-Process -Name $ProcessName)
        if ($P.Count -eq 0) {
            return
        }
    }
    elseif ($null -ne $ProcessID) {
        $P = @(Get-Process -Id $ProcessID)
        if ($P.Count -eq 0) {
            return
        }
    }
    elseif ($IncludeProcess) {
        $P = @(Get-Process)
    }
    $P | ForEach-Object { $Processes["$($_.Id)"] = $_ }

    Write-Verbose "There are $($Processes.Count) processes"

    #  Retrieve list of window handle pointers
    $hWnds = [User32.SetGetWindow]::GetWindows()
    if ($WindowHandles.Count -ne 0) {
        [System.Collections.ArrayList]$hWnds = $hWnds | Where-Object { $_ -in $WindowHandles }
    }
    if ($hWnds.Count -eq 0) {
        return
    }

    Write-Verbose "There are $($hWnds.Count) window handles"

    #  Quick method to create a string of ~293 characters.  Longer titles will be truncated.
    [String]$tempString = (0..100)
    [int]$stringLength = $tempString.Length
    [System.Collections.ArrayList]$Windows = @()


    foreach ($hWnd in $hWnds) {
        try {
            [String]$ClassName = $null
            [String]$WindowText = $null
            [UInt32]$ThreadID = $null
            [UInt32]$ProcID = $null
            $ClassNameLength = [User32.SetGetWindow]::GetClassName($hWnd, $tempString, $stringLength)
            $ClassName = $tempString.Substring(0, $ClassNameLength)
            $WindowTextLength = [User32.SetGetWindow]::GetWindowText($hWnd, $tempString, $stringLength)
            $WindowText = $tempString.Substring(0, $WindowTextLength)
            $ThreadID = [User32.SetGetWindow]::GetWindowThreadProcessId($hWnd, [ref]$ProcID)
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
            Process      = $null
        }
        $null = $Windows.Add($Window)
    }

    if ($Processes.Count -gt 0) {
        foreach ($Window in $Windows) {
            if ($Processes.ContainsKey("$($Window.ProcessID)")) {
                $Window.Process = $Processes["$($Window.ProcessID)"]
            }
        }
    }

    if ($null -ne $ProcessName -or $null -ne $ProcessID) {
        $FilteredWindows = @($Windows | Where-Object { $null -ne $_.Process })
    }
    else {
        $FilteredWindows = @($Windows | Where-Object { $true })
    }

    if ($WindowClass) {
        $FilteredWindows = $FilteredWindows | Where-Object { $_.WindowClass -like $WindowClass }
    }
    if ($WindowTitle) {
        $FilteredWindows = $FilteredWindows | Where-Object { $_.WindowTitle -like $WindowTitle }
    }

    Write-Verbose "There are $($FilteredWindows.Count) filtered window handles"

    $FilteredWindows | Write-Output
}
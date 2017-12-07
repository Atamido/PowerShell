

Function Set-Transparency {
    Param(
        [Parameter(Position=0)][ValidateScript({$_.Length -gt 0})][String]$WindowTitle = '',
        [Parameter(Position=1)][ValidateScript({$_.Length -gt 0})][String]$WindowClass = '',
        [Parameter(Position=3)][ValidateRange(0,255)][int]$Opacity=200,
        [Parameter(Position=4)][int[]]$WindowHandle=@()
    )

    #  List of available values for WindowAction
    #  Default '0' is 'hide window'
    #  https://msdn.microsoft.com/en-us/library/windows/desktop/ms633548(v=vs.85).aspx
    
    #  Bool flags for comparisons so there are less string comparisons, which are slow
    [Bool]$WT = $true
    [Bool]$WC = $true
    
    if ($WindowTitle -eq '') {
        $WT = $false
    }
    if ($WindowClass -eq '') {
        $WC = $false
    }

    $MethodDefinition = @'
        [DllImport("user32.dll")]
        public static extern IntPtr FindWindow(String sClassName, String sAppName);

        [DllImport("user32.dll")]
        public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

        [DllImport("user32.dll")]
        public static extern int SetWindowLongPtr(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll")]
        public static extern int GetWindowLongPtr(IntPtr hWnd, int nIndex);
        
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, string strText, int maxCount);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowTextLength(IntPtr hWnd);

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


    if (-not ([System.Management.Automation.PSTypeName]'User32.SetTransparency').Type) {
        Add-Type -MemberDefinition $MethodDefinition -Name 'SetTransparency' -Namespace 'User32' | Out-Null
    }

    [Int]$GWL_EXSTYLE = -20;
    [Int]$WS_EX_LAYERED = 0x80000;
    [Int]$LWA_ALPHA = 0x2;
    [Int]$LWA_COLORKEY = 0x1;


    if ($WindowHandle.Count -eq 0) {
    #  Retrieve list of window handle pointers
        $hwnds = [User32.SetTransparency]::GetWindows()
    } else {
        [System.Collections.ArrayList]$hwnds = $WindowHandle
    }

    Write-Verbose "There are $($hwnds.Count) window handles"

    #  Quick method to create a string of ~290 characters
    [String]$tempString = (0..100)
    $stringLength = $tempString.Length
    [System.Collections.ArrayList]$Windows = @()


    foreach ($hwnd in $hwnds) {
        $ClassNameLength = [User32.SetTransparency]::GetClassName($hWnd, $tempString, $stringLength)
        $ClassName = $tempString.Substring(0,$ClassNameLength)
        $WindowTextLength = [User32.SetTransparency]::GetWindowText($hWnd, $tempString, $stringLength)
        $WindowText = $tempString.Substring(0,$WindowTextLength)
        if ($ClassNameLength -ne 0 -or $WindowTextLength -ne 0) {
            $Window = New-Object -TypeName psobject -Property @{hwnd = $hwnd; ClassName = $ClassName; WindowText = $WindowText}
            $Windows.Add($Window) | Out-Null
        }
    }

    Write-Verbose "There are $($Windows.Count) window handles with a title or class"

    if ($WindowHandle.Count -eq 0) {
        $FilteredWindows = $Windows | Where-Object -FilterScript {($WC -and $_.ClassName -like $WindowClass) -or ($WT -and $_.WindowText -like $WindowTitle)}
    } else {
        $FilteredWindows = $Windows
    }
    
    Write-Verbose "There are $($FilteredWindows.Count) filtered window handles"

    $FilteredWindows | ForEach-Object {
        $win = $_
        $WindowLong = [User32.SetTransparency]::GetWindowLongPtr($win.hWnd, $GWL_EXSTYLE)
        $dwNewLong = $WindowLong -bxor $WS_EX_LAYERED
        [void][User32.SetTransparency]::SetWindowLongPtr($win.hWnd, $GWL_EXSTYLE, $dwNewLong)
        $win | Add-Member -Type NoteProperty -Name 'Success' -Value ([User32.SetTransparency]::SetLayeredWindowAttributes($win.hWnd, 0, $Opacity, $LWA_ALPHA))
    }

    Return $FilteredWindows
}



Function Hide-Window {
    Param(
        [Parameter(Position=0,Mandatory=$true)][String]$Title,
        [Parameter(Position=1)][int]$WindowAction=0
    )

    #  Valid values for WindowAction can be found on the MSDN documentation for the ShowWindow function
    #  https://msdn.microsoft.com/en-us/library/ms633548%28VS.85%29.aspx

    Add-Type -TypeDefinition @'
        using System;
        using System.Collections;
        using System.Collections.Generic;
        using System.Runtime.InteropServices;
        using System.Text;
        using Microsoft.Win32;
        namespace WindowFunctions {
            public class Setter {


                [DllImport("user32.dll", CharSet = CharSet.Unicode)]
                private static extern int GetWindowText(IntPtr hWnd, StringBuilder strText, int maxCount);

                [DllImport("user32.dll", CharSet = CharSet.Unicode)]
                private static extern int GetWindowTextLength(IntPtr hWnd);

                [DllImport("user32.dll")]
                private static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

                [DllImport("user32.dll")]
                private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

                // Delegate to filter which windows to include 
                public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

                /// <summary> Get the text for the window pointed to by hWnd </summary>
                public static string GetMyWindowText(IntPtr hWnd)
                {
                    int size = GetWindowTextLength(hWnd);
                    if (size > 0)
                    {
                        var builder = new StringBuilder(size + 1);
                        GetWindowText(hWnd, builder, builder.Capacity);
                        return builder.ToString();
                    }

                    return String.Empty;
                }

                /// <summary> Find all windows that match the given filter </summary>
                /// <param name="filter"> A delegate that returns true for windows
                ///    that should be returned and false for windows that should
                ///    not be returned </param>
                public static IEnumerable<IntPtr> FindWindows(EnumWindowsProc filter)
                {
                    IntPtr found = IntPtr.Zero;
                    List<IntPtr> windows = new List<IntPtr>();

                    EnumWindows(delegate(IntPtr wnd, IntPtr param)
                    {
                        if (filter(wnd, param))
                        {
                            // only add the windows that pass the filter
                            windows.Add(wnd);
                        }

                        // but return true here so that we iterate all windows
                        return true;
                    }, IntPtr.Zero);

                    return windows;
                }

                /// <summary> Find all windows that contain the given title text </summary>
                /// <param name="titleText"> The text that the window title must contain. </param>
                public static IEnumerable<IntPtr> FindWindowsWithText(string titleText)
                {
                    return FindWindows(delegate(IntPtr wnd, IntPtr param)
                    {
                        return GetMyWindowText(wnd).Contains(titleText);
                    });
                }

                /// <summary> Count all windows that contain the given title text </summary>
                /// <param name="titleText"> The text that the window title must contain. </param>
                public static Int32 CountWindowsWithText(string titleText)
                {
                    List<IntPtr> cList = new List<IntPtr>();
                    IEnumerable<IntPtr> windows = FindWindowsWithText(titleText);
                    cList.AddRange(windows);
                    return cList.Count;
                }

                /// <summary> Count all windows that contain the given title text </summary>
                /// <param name="titleText"> The text that the window title must contain. </param>
                public static Int32 HideWindowsWithText(string titleText, int nCmdShow)
                {
                    List<IntPtr> cList = new List<IntPtr>();
                    IEnumerable<IntPtr> windows = FindWindowsWithText(titleText);
                    cList.AddRange(windows);
                    if(cList.Count > 0)
                    {
                        foreach (IntPtr window in windows)
                        {
                            ShowWindow(window, nCmdShow);
                        }
                    }
                    return cList.Count;
                }
            }
        }
'@


    [WindowFunctions.Setter]::HideWindowsWithText($Title, $WindowAction)
}

$windows = Hide-Window -Title 'FirstUXWnd' -WindowAction 0
Write-Host "Hid $($windows) windows"


# Shared WPF dialog utilities for Claude Code notification hooks
# Dot-source this from each dialog: . "$PSScriptRoot\dialog-common.ps1"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class AcrylicHelper
{
  [DllImport("user32.dll")]
  private static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WinCompositionAttrData data);

  [DllImport("dwmapi.dll")]
  private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

  [StructLayout(LayoutKind.Sequential)]
  private struct WinCompositionAttrData
  {
    public int Attribute;
    public IntPtr Data;
    public int SizeOfData;
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct AccentPolicy
  {
    public int AccentState;
    public int AccentFlags;
    public uint GradientColor;
    public int AnimationId;
  }

  public static void EnableAcrylic(IntPtr hwnd, byte r, byte g, byte b, byte alpha)
  {
    int rounded = 2;
    DwmSetWindowAttribute(hwnd, 33, ref rounded, sizeof(int));

    var accent = new AccentPolicy
    {
      AccentState = 4,
      AccentFlags = 2,
      GradientColor = ((uint)alpha << 24) | ((uint)b << 16) | ((uint)g << 8) | r
    };

    int accentSize = Marshal.SizeOf(accent);
    IntPtr accentPtr = Marshal.AllocHGlobal(accentSize);
    Marshal.StructureToPtr(accent, accentPtr, false);

    var data = new WinCompositionAttrData
    {
      Attribute = 19,
      Data = accentPtr,
      SizeOfData = accentSize
    };

    SetWindowCompositionAttribute(hwnd, ref data);
    Marshal.FreeHGlobal(accentPtr);
  }
}
"@ -Language CSharp

function New-AppIcon([string]$Path)
{
  if (-not $Path -or -not (Test-Path $Path)) { return $null }
  $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
  $bmp.BeginInit()
  $bmp.UriSource = New-Object System.Uri($Path, [System.UriKind]::Absolute)
  $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bmp.EndInit()
  return $bmp
}

function Add-SourceBadge([System.Windows.Window]$Window, [string]$Source)
{
  if (-not $Source) { return }

  $theme = switch ($Source)
  {
    "WSL2"    { @{ Bg = "#E95420"; Border = "#44E95420"; Label = "WSL" } }
    "Windows" { @{ Bg = "#0078D4"; Border = "#440078D4"; Label = "WIN" } }
    default   { @{ Bg = "#666666"; Border = "#44666666"; Label = $Source } }
  }

  $bc = [System.Windows.Media.BrushConverter]::new()

  # Pill badge in header
  $header = $Window.FindName("HeaderPanel")
  if ($header)
  {
    $badge = New-Object System.Windows.Controls.Border
    $badge.Background = $bc.ConvertFrom($theme.Bg)
    $badge.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $badge.Padding = [System.Windows.Thickness]::new(7, 2, 7, 2)
    $badge.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $badge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $badge.Opacity = 0.9

    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $theme.Label
    $label.FontSize = 10
    $label.FontWeight = [System.Windows.FontWeights]::Bold
    $label.Foreground = $bc.ConvertFrom("#ffffff")
    $label.FontFamily = New-Object System.Windows.Media.FontFamily("Cascadia Code,Consolas,Courier New")

    $badge.Child = $label
    $header.Children.Add($badge) | Out-Null
  }

}

function Play-NotificationSound
{
  $player = New-Object System.Media.SoundPlayer
  $player.SoundLocation = [System.IO.Path]::Combine($env:SystemRoot, "Media", "Windows Notify System Generic.wav")
  try { $player.Play() } catch {}
}

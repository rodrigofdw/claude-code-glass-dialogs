param(
  [string]$SentinelFile = "",
  [string]$IconPath = "",
  [string]$Source = ""
)

. "$PSScriptRoot\dialog-common.ps1"

if (-not $SentinelFile -or -not (Test-Path $SentinelFile))
{
  exit 0
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Code — Working" Width="300" SizeToContent="Height"
        WindowStartupLocation="Manual" Topmost="True" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" ResizeMode="NoResize" Opacity="0">
  <Border CornerRadius="12" BorderBrush="#44ffffff" BorderThickness="1" Background="Transparent"
          Padding="16,12,16,12">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header: icon + title + source badge -->
      <StackPanel Name="HeaderPanel" Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
        <Image Name="AppIcon" Width="22" Height="22" Margin="0,0,8,0"
               RenderOptions.BitmapScalingMode="HighQuality" VerticalAlignment="Center"/>
        <TextBlock Text="Claude is working" FontSize="14" FontWeight="SemiBold"
                   Foreground="#e0e0e0" VerticalAlignment="Center"/>
      </StackPanel>

      <!-- Animated progress bar -->
      <Border Grid.Row="1" Height="3" CornerRadius="2" Background="#20ffffff" Margin="0,0,0,10"
              ClipToBounds="True">
        <Border Name="ProgressGlow" Width="80" Height="3" CornerRadius="2"
                HorizontalAlignment="Left" Margin="-80,0,0,0">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
              <GradientStop Color="#00a6e3a1" Offset="0"/>
              <GradientStop Color="#cca6e3a1" Offset="0.5"/>
              <GradientStop Color="#00a6e3a1" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
        </Border>
      </Border>

      <!-- Elapsed time -->
      <StackPanel Grid.Row="2" Orientation="Horizontal">
        <Ellipse Name="BreathDot" Width="7" Height="7" Margin="0,0,8,0" VerticalAlignment="Center">
          <Ellipse.Fill>
            <RadialGradientBrush>
              <GradientStop Color="#a6e3a1" Offset="0"/>
              <GradientStop Color="#60a6e3a1" Offset="1"/>
            </RadialGradientBrush>
          </Ellipse.Fill>
        </Ellipse>
        <TextBlock Name="ElapsedText" Text="0s" FontSize="12"
                   Foreground="#88ffffff" VerticalAlignment="Center"
                   FontFamily="Cascadia Code,Consolas,Courier New"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
"@

$window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$icon = New-AppIcon $IconPath
if ($icon) { $window.FindName("AppIcon").Source = $icon }
Add-SourceBadge $window $Source

$script:isClosing = $false
function Invoke-CloseWithFade
{
  if ($script:isClosing) { return }
  $script:isClosing = $true
  $anim = New-Object System.Windows.Media.Animation.DoubleAnimation(
    1, 0, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(400)))
  $anim.Add_Completed({ $window.Close() })
  $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
}

# Position bottom-right, offset upward so it doesn't overlap other dialogs
$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Add_Loaded({
  $window.Left = $workArea.Right - $window.ActualWidth - 4
  $window.Top = $workArea.Bottom - $window.ActualHeight - 4
  $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
  [AcrylicHelper]::EnableAcrylic($hwnd, 70, 70, 70, 0x77)
})

$progressGlow = $window.FindName("ProgressGlow")
$breathDot = $window.FindName("BreathDot")

$window.Add_ContentRendered({
  $window.Activate()

  # Fade in
  $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation(
    0, 1, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(400)))
  $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)

  # Sweeping progress glow: animate Margin.Left from -80 to container width
  $sweep = New-Object System.Windows.Media.Animation.ThicknessAnimation
  $sweep.From = [System.Windows.Thickness]::new(-80, 0, 0, 0)
  $sweep.To = [System.Windows.Thickness]::new(300, 0, 0, 0)
  $sweep.Duration = [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(1800))
  $sweep.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $progressGlow.BeginAnimation([System.Windows.FrameworkElement]::MarginProperty, $sweep)

  # Breathing dot: scale pulse
  $breathScale = New-Object System.Windows.Media.Animation.DoubleAnimation(
    1.0, 1.6, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(1200)))
  $breathScale.AutoReverse = $true
  $breathScale.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $breathScale.EasingFunction = New-Object System.Windows.Media.Animation.SineEase

  $breathOpacity = New-Object System.Windows.Media.Animation.DoubleAnimation(
    1.0, 0.4, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(1200)))
  $breathOpacity.AutoReverse = $true
  $breathOpacity.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
  $breathOpacity.EasingFunction = New-Object System.Windows.Media.Animation.SineEase

  $scaleTransform = New-Object System.Windows.Media.ScaleTransform(1, 1, 3.5, 3.5)
  $breathDot.RenderTransform = $scaleTransform
  $scaleTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $breathScale)
  $scaleTransform.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $breathScale)
  $breathDot.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $breathOpacity)
})

# Timer: elapsed time + sentinel check
$script:startTime = Get-Date
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [System.TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  if (-not (Test-Path $SentinelFile))
  {
    $timer.Stop()
    Invoke-CloseWithFade
    return
  }

  $elapsed = (Get-Date) - $script:startTime
  $txt = if ($elapsed.TotalHours -ge 1) { "{0:h\:mm\:ss}" -f $elapsed }
         elseif ($elapsed.TotalMinutes -ge 1) { "{0:m\:ss}" -f $elapsed }
         else { "{0:s\s}" -f $elapsed }
  $window.FindName("ElapsedText").Text = $txt
})
$timer.Start()

# Escape to manually dismiss
$window.Add_KeyDown({
  param($s, $e)
  if ($e.Key -eq "Escape") { Invoke-CloseWithFade }
})

$window.ShowDialog() | Out-Null
$timer.Stop()
Remove-Item $SentinelFile -Force -ErrorAction SilentlyContinue

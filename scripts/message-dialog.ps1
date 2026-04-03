param(
  [Parameter(Mandatory)]
  [string]$Title,
  [Parameter(Mandatory)]
  [string]$Message,
  [string]$IconPath = "",
  [int]$TimeoutSeconds = 30,
  [switch]$PlaySound,
  [string]$Source = ""
)

. "$PSScriptRoot\dialog-common.ps1"

if ($PlaySound) { Play-NotificationSound }

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Code" Width="520" SizeToContent="Height" MaxHeight="500"
        WindowStartupLocation="Manual" Topmost="True" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="True" ResizeMode="NoResize" Opacity="0">
  <Window.Resources>
    <Style x:Key="ActionBtn" TargetType="Button">
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Height" Value="34"/>
      <Setter Property="MinWidth" Value="90"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="14,0">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter Property="Opacity" Value="0.7"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="12" BorderBrush="#44ffffff" BorderThickness="1" Background="Transparent">
    <Grid Margin="20,16,20,16">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Name="HeaderPanel" Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,14">
        <Image Name="AppIcon" Width="26" Height="26" Margin="0,0,10,0"
               RenderOptions.BitmapScalingMode="HighQuality"/>
        <TextBlock Name="TitleText" FontSize="15" FontWeight="SemiBold"
                   Foreground="#ffffff" VerticalAlignment="Center"/>
      </StackPanel>
      <Border Grid.Row="1" Background="#20000000" CornerRadius="8" Padding="14" Margin="0,0,0,14" MaxHeight="360">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <TextBlock Name="MessageText" FontSize="13" Foreground="#e0e0e0"
                     FontFamily="Cascadia Code,Consolas,Courier New" TextWrapping="Wrap" LineHeight="20"/>
        </ScrollViewer>
      </Border>
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Name="CountdownText" Grid.Column="0" FontSize="12" Foreground="#88ffffff"
                   VerticalAlignment="Center" Margin="2,0,0,0"/>
        <Button Name="DismissBtn" Grid.Column="2" Content="Dismiss"
                Background="#60ffffff" Foreground="#1e1e2e" Style="{StaticResource ActionBtn}"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

$window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))

$window.FindName("TitleText").Text = $Title
$window.FindName("MessageText").Text = $Message
$window.FindName("CountdownText").Text = "${TimeoutSeconds}s"
$icon = New-AppIcon $IconPath
if ($icon) { $window.FindName("AppIcon").Source = $icon }
Add-SourceBadge $window $Source

$script:isClosing = $false
function Invoke-CloseWithFade
{
  if ($script:isClosing) { return }
  $script:isClosing = $true
  $anim = New-Object System.Windows.Media.Animation.DoubleAnimation(
    1, 0, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(180)))
  $anim.Add_Completed({ $window.Close() })
  $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $anim)
}

$window.FindName("DismissBtn").Add_Click({ Invoke-CloseWithFade })
$window.Add_KeyDown({
  param($s, $e)
  if ($e.Key -eq "Escape" -or $e.Key -eq "Return" -or $e.Key -eq "Space")
  { Invoke-CloseWithFade }
})

$script:countdown = $TimeoutSeconds
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [System.TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  $script:countdown--
  $window.FindName("CountdownText").Text = "$($script:countdown)s"
  if ($script:countdown -le 0) { $timer.Stop(); Invoke-CloseWithFade }
})
$timer.Start()

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Add_Loaded({
  $window.Left = $workArea.Right - $window.ActualWidth - 4
  $window.Top = $workArea.Bottom - $window.ActualHeight - 4
  $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
  [AcrylicHelper]::EnableAcrylic($hwnd, 100, 100, 100, 0x66)
})
$window.Add_ContentRendered({
  $window.Activate()
  $window.FindName("DismissBtn").Focus()
  $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation(
    0, 1, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(200)))
  $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)
})

$window.ShowDialog() | Out-Null
$timer.Stop()

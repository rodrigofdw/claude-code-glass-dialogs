param(
  [Parameter(Mandatory)]
  [string]$JsonFile,
  [string]$IconPath = "",
  [string]$Source = "",
  [int]$TimeoutSeconds = 45
)

. "$PSScriptRoot\dialog-common.ps1"

$hookData = Get-Content $JsonFile -Raw | ConvertFrom-Json
$toolName = $hookData.tool_name
$toolInput = $hookData.tool_input
$permSuggestions = $hookData.permission_suggestions

$detail = switch ($toolName)
{
  "Bash"  { $toolInput.command }
  "Edit"  { "$($toolInput.file_path)" }
  "Write" { "$($toolInput.file_path)" }
  "Read"  { "$($toolInput.file_path)" }
  "Glob"  { "$($toolInput.pattern) in $($toolInput.path)" }
  "Grep"  { "/$($toolInput.pattern)/ in $($toolInput.path)" }
  default { ($toolInput | ConvertTo-Json -Compress -Depth 2) }
}
if ($detail.Length -gt 400) { $detail = $detail.Substring(0, 397) + "..." }

# Build "Always Allow" label from the first allow suggestion
$alwaysLabel = $null
$alwaysSuggestion = $null
if ($permSuggestions)
{
  foreach ($s in $permSuggestions)
  {
    if ($s.behavior -eq "allow" -and $s.type -eq "addRules" -and $s.rules)
    {
      $alwaysSuggestion = $s
      $ruleDesc = ($s.rules | ForEach-Object {
        if ($_.ruleContent) { "$($_.toolName)($($_.ruleContent))" }
        else { $_.toolName }
      }) -join ", "
      $alwaysLabel = "Always allow: $ruleDesc"
      break
    }
  }
}

# Build XAML for the Always button row (full-width, above Allow/Deny)
$alwaysRowXaml = ""
$alwaysRowDef = ""
$buttonsGridRow = "3"
if ($alwaysLabel)
{
  $alwaysRowDef = '<RowDefinition Height="Auto"/>'
  $buttonsGridRow = "4"
  $alwaysRowXaml = @"
      <Button Name="AlwaysBtn" Grid.Row="3" Content="$([System.Security.SecurityElement]::Escape($alwaysLabel))"
              HorizontalAlignment="Stretch" Margin="0,0,0,10"
              Background="#89b4fa" Foreground="#1e1e2e" Style="{StaticResource ActionBtn}"/>
"@
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Code" Width="460" SizeToContent="Height"
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
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
$alwaysRowDef
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <StackPanel Name="HeaderPanel" Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,14">
        <Image Name="AppIcon" Width="26" Height="26" Margin="0,0,10,0"
               RenderOptions.BitmapScalingMode="HighQuality"/>
        <TextBlock Text="Claude Code" FontSize="15" FontWeight="SemiBold"
                   Foreground="#ffffff" VerticalAlignment="Center"/>
        <TextBlock Text=" — Permission Request" FontSize="15"
                   Foreground="#cccccc" VerticalAlignment="Center"/>
      </StackPanel>
      <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
        <Border Background="#40ffffff" CornerRadius="4" Padding="8,3">
          <TextBlock Name="ToolNameText" FontSize="13" Foreground="#80bbff" FontWeight="SemiBold"
                     FontFamily="Cascadia Code,Consolas,Courier New"/>
        </Border>
      </StackPanel>
      <Border Grid.Row="2" Background="#30000000" CornerRadius="8" Padding="12" Margin="0,0,0,16" MaxHeight="140">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <TextBlock Name="DetailText" FontSize="12.5" Foreground="#e0e0e0"
                     FontFamily="Cascadia Code,Consolas,Courier New" TextWrapping="Wrap" LineHeight="18"/>
        </ScrollViewer>
      </Border>
$alwaysRowXaml
      <Grid Grid.Row="$buttonsGridRow">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Name="CountdownText" Grid.Column="0" FontSize="12" Foreground="#88ffffff"
                   VerticalAlignment="Center" Margin="2,0,0,0"/>
        <Button Name="AllowBtn" Grid.Column="2" Content="Allow" Margin="0,0,10,0"
                Background="#a6e3a1" Foreground="#1e1e2e" Style="{StaticResource ActionBtn}"/>
        <Button Name="DenyBtn" Grid.Column="3" Content="Deny"
                Background="#f38ba8" Foreground="#1e1e2e" Style="{StaticResource ActionBtn}"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

$window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$window.Tag = "ask"

$window.FindName("ToolNameText").Text = $toolName
$window.FindName("DetailText").Text = $detail
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

# Button handlers
$window.FindName("AllowBtn").Add_Click({ $window.Tag = "allow"; Invoke-CloseWithFade })
$window.FindName("DenyBtn").Add_Click({ $window.Tag = "deny"; Invoke-CloseWithFade })

$alwaysBtn = $window.FindName("AlwaysBtn")
if ($alwaysBtn)
{
  $alwaysBtn.Add_Click({ $window.Tag = "always"; Invoke-CloseWithFade })
}

# Keyboard: Enter/Y/A = Allow, Escape/N/D = Deny, S = Always
$window.Add_KeyDown({
  param($s, $e)
  if ($e.Key -eq "Return" -or $e.Key -eq "Y")
  { $window.Tag = "allow"; Invoke-CloseWithFade }
  elseif ($e.Key -eq "Escape" -or $e.Key -eq "N" -or $e.Key -eq "D")
  { $window.Tag = "deny"; Invoke-CloseWithFade }
  elseif ($e.Key -eq "S" -or $e.Key -eq "A")
  {
    if ($alwaysBtn) { $window.Tag = "always" } else { $window.Tag = "allow" }
    Invoke-CloseWithFade
  }
})

$script:countdown = $TimeoutSeconds
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [System.TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  $script:countdown--
  $window.FindName("CountdownText").Text = "$($script:countdown)s"
  if ($script:countdown -le 0)
  { $timer.Stop(); $window.Tag = "ask"; Invoke-CloseWithFade }
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
  if ($alwaysBtn) { $alwaysBtn.Focus() } else { $window.FindName("AllowBtn").Focus() }
  $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation(
    0, 1, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(200)))
  $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)
})

$window.ShowDialog() | Out-Null
$timer.Stop()

# Output: "allow", "deny", "ask", or "always::JSON"
if ($window.Tag -eq "always" -and $alwaysSuggestion)
{
  $json = $alwaysSuggestion | ConvertTo-Json -Compress -Depth 5
  Write-Output "always::$json"
}
else
{
  Write-Output $window.Tag
}

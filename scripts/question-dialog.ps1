param(
  [Parameter(Mandatory)]
  [string]$JsonFile,
  [string]$IconPath = "",
  [string]$Source = "",
  [int]$TimeoutSeconds = 120
)

. "$PSScriptRoot\dialog-common.ps1"

$hookData = Get-Content $JsonFile -Raw | ConvertFrom-Json
$questions = $hookData.tool_input.questions
if (-not $questions -or $questions.Count -eq 0) { Write-Output "::SKIP::"; exit 0 }

# ── State ───────────────────────────────────────────────────────────
$script:selections = @{}
$script:otherTexts = @{}
$script:optionCards = @{}
$script:focusedQ = 0
$script:focusedO = @{}
$script:otherBoxes = @{}

for ($i = 0; $i -lt $questions.Count; $i++)
{
  $script:selections[$i] = if ($questions[$i].multiSelect) { @{} } else { $null }
  $script:otherTexts[$i] = ""
}

# ── Colors ──────────────────────────────────────────────────────────
$bc = [System.Windows.Media.BrushConverter]::new()
$colorSelected   = $bc.ConvertFrom("#3089b4fa")
$colorUnselected = $bc.ConvertFrom("#18ffffff")
$colorBorderSel  = $bc.ConvertFrom("#89b4fa")
$colorBorderNorm = $bc.ConvertFrom("#30ffffff")
$colorTextPri    = $bc.ConvertFrom("#f0f0f0")
$colorTextSec    = $bc.ConvertFrom("#aaaaaa")
$colorDot        = $bc.ConvertFrom("#89b4fa")
$colorDotEmpty   = $bc.ConvertFrom("#555555")
$colorBadgeBg    = $bc.ConvertFrom("#40ffffff")
$colorBadgeText  = $bc.ConvertFrom("#89b4fa")
$colorFocusRing  = $bc.ConvertFrom("#aaddff")

# ── Helpers ─────────────────────────────────────────────────────────
function Test-IsSelected([int]$qIdx, [int]$optIdx)
{
  $q = $questions[$qIdx]
  if ($q.multiSelect) { $script:selections[$qIdx].ContainsKey($optIdx) -and $script:selections[$qIdx][$optIdx] }
  else { $script:selections[$qIdx] -eq $optIdx }
}

function Set-OptionSelected([int]$qIdx, [int]$optIdx)
{
  $q = $questions[$qIdx]
  if ($optIdx -eq -1)
  {
    if ($q.multiSelect)
    {
      $script:selections[$qIdx][-1] = $true
      foreach ($k in @($script:selections[$qIdx].Keys | Where-Object { $_ -ne -1 }))
      { $script:selections[$qIdx][$k] = $false }
    }
    else { $script:selections[$qIdx] = -1 }
  }
  else
  {
    if ($q.multiSelect)
    {
      $cur = $script:selections[$qIdx].ContainsKey($optIdx) -and $script:selections[$qIdx][$optIdx]
      $script:selections[$qIdx][$optIdx] = -not $cur
      if ($script:selections[$qIdx][$optIdx]) { $script:selections[$qIdx][-1] = $false }
    }
    else { $script:selections[$qIdx] = $optIdx }
  }
}

function Update-OptionVisuals([int]$qIdx)
{
  $q = $questions[$qIdx]
  foreach ($entry in $script:optionCards[$qIdx])
  {
    $sel = Test-IsSelected $qIdx $entry.Index
    $entry.Card.Background = if ($sel) { $colorSelected } else { $colorUnselected }
    $entry.Card.BorderBrush = if ($sel) { $colorBorderSel } else { $colorBorderNorm }
    $multi = $q.multiSelect
    $entry.Dot.Text = if ($sel) { if ($multi) { [char]0x2611 } else { [char]0x25C9 } }
                      else { if ($multi) { [char]0x2610 } else { [char]0x25CB } }
    $entry.Dot.Foreground = if ($sel) { $colorDot } else { $colorDotEmpty }
  }
}

function Update-FocusRing()
{
  foreach ($qIdx in $script:optionCards.Keys)
  {
    foreach ($entry in $script:optionCards[$qIdx])
    {
      $sel = Test-IsSelected $qIdx $entry.Index
      $entry.Card.BorderBrush = if ($sel) { $colorBorderSel } else { $colorBorderNorm }
      $entry.Card.BorderThickness = [System.Windows.Thickness]::new(1.5)
    }
  }
  $fo = $script:focusedO[$script:focusedQ]
  if ($null -ne $fo)
  {
    $fe = $script:optionCards[$script:focusedQ] | Where-Object { $_.Index -eq $fo }
    if ($fe) { $fe.Card.BorderBrush = $colorFocusRing; $fe.Card.BorderThickness = [System.Windows.Thickness]::new(2) }
  }
}

function Select-FocusedOption()
{
  $fq = $script:focusedQ; $fo = $script:focusedO[$fq]
  if ($null -eq $fo) { return }
  Set-OptionSelected $fq $fo
  Update-OptionVisuals $fq; Update-FocusRing
  if ($fo -eq -1 -and $script:otherBoxes.ContainsKey($fq)) { $script:otherBoxes[$fq].Focus() }
}

function Move-Focus([int]$delta)
{
  $fq = $script:focusedQ
  $total = $questions[$fq].options.Count + 1
  $flat = if ($script:focusedO[$fq] -eq -1) { $total - 1 } else { $script:focusedO[$fq] }
  $flat += $delta

  if ($flat -lt 0 -and $fq -gt 0)
  { $script:focusedQ = --$fq; $total = $questions[$fq].options.Count + 1; $flat = $total - 1 }
  elseif ($flat -ge $total -and $fq -lt ($questions.Count - 1))
  { $script:focusedQ = ++$fq; $flat = 0 }
  else { $flat = [Math]::Max(0, [Math]::Min($flat, $total - 1)) }

  $script:focusedO[$fq] = if ($flat -eq ($questions[$fq].options.Count)) { -1 } else { $flat }
  Update-FocusRing
  if ($script:focusedO[$fq] -eq -1 -and $script:otherBoxes.ContainsKey($fq))
  { $script:otherBoxes[$fq].Focus() }
  else { $window.Focus() }
}

# ── XAML ────────────────────────────────────────────────────────────
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Code" Width="500" SizeToContent="Height" MaxHeight="720"
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
        <TextBlock Text="Claude Code" FontSize="15" FontWeight="SemiBold"
                   Foreground="#ffffff" VerticalAlignment="Center"/>
        <TextBlock Text=" — Question" FontSize="15"
                   Foreground="#cccccc" VerticalAlignment="Center"/>
      </StackPanel>
      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled" Margin="0,0,0,14">
        <StackPanel Name="QuestionsPanel" />
      </ScrollViewer>
      <Grid Grid.Row="2">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Name="CountdownText" Grid.Column="0" FontSize="12" Foreground="#88ffffff"
                   VerticalAlignment="Center" Margin="2,0,0,0"/>
        <Button Name="SubmitBtn" Grid.Column="2" Content="Send" Margin="0,0,10,0"
                Background="#89b4fa" Foreground="#1e1e2e" Style="{StaticResource ActionBtn}"/>
        <Button Name="SkipBtn" Grid.Column="3" Content="Skip"
                Background="#60ffffff" Foreground="#1e1e2e" Style="{StaticResource ActionBtn}"/>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

$window = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$window.Tag = "::SKIP::"
$questionsPanel = $window.FindName("QuestionsPanel")
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

$monoFont = New-Object System.Windows.Media.FontFamily("Cascadia Code,Consolas,Courier New")

# ── Build UI for each question ──────────────────────────────────────
for ($qIdx = 0; $qIdx -lt $questions.Count; $qIdx++)
{
  $q = $questions[$qIdx]
  $script:optionCards[$qIdx] = @()
  $script:focusedO[$qIdx] = 0
  $cq = $qIdx

  $qPanel = New-Object System.Windows.Controls.StackPanel
  if ($qIdx -gt 0) { $qPanel.Margin = [System.Windows.Thickness]::new(0, 16, 0, 0) }

  $hb = New-Object System.Windows.Controls.Border
  $hb.Background = $colorBadgeBg; $hb.CornerRadius = [System.Windows.CornerRadius]::new(4)
  $hb.Padding = [System.Windows.Thickness]::new(8, 3, 8, 3)
  $hb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
  $hb.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
  $ht = New-Object System.Windows.Controls.TextBlock
  $ht.Text = $q.header; $ht.FontSize = 12; $ht.FontWeight = [System.Windows.FontWeights]::SemiBold
  $ht.Foreground = $colorBadgeText; $ht.FontFamily = $monoFont
  $hb.Child = $ht; $qPanel.Children.Add($hb) | Out-Null

  $qt = New-Object System.Windows.Controls.TextBlock
  $qt.Text = $q.question; $qt.FontSize = 13.5; $qt.Foreground = $colorTextPri
  $qt.TextWrapping = [System.Windows.TextWrapping]::Wrap; $qt.LineHeight = 20
  $qt.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
  $qPanel.Children.Add($qt) | Out-Null

  if ($q.multiSelect)
  {
    $hi = New-Object System.Windows.Controls.TextBlock
    $hi.Text = "Select one or more:"; $hi.FontSize = 11; $hi.Foreground = $colorTextSec
    $hi.FontStyle = [System.Windows.FontStyles]::Italic
    $hi.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $qPanel.Children.Add($hi) | Out-Null
  }

  for ($oIdx = 0; $oIdx -lt $q.options.Count; $oIdx++)
  {
    $opt = $q.options[$oIdx]; $co = $oIdx

    $card = New-Object System.Windows.Controls.Border
    $card.Background = $colorUnselected; $card.BorderBrush = $colorBorderNorm
    $card.BorderThickness = [System.Windows.Thickness]::new(1.5)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
    $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $card.Cursor = [System.Windows.Input.Cursors]::Hand

    $cg = New-Object System.Windows.Controls.Grid
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(22)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $cg.ColumnDefinitions.Add($c0); $cg.ColumnDefinitions.Add($c1)

    $dot = New-Object System.Windows.Controls.TextBlock
    $dot.Text = if ($q.multiSelect) { [char]0x2610 } else { [char]0x25CB }
    $dot.FontSize = 16; $dot.Foreground = $colorDotEmpty
    $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    $dot.Margin = [System.Windows.Thickness]::new(0, 1, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($dot, 0); $cg.Children.Add($dot) | Out-Null

    $ts = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($ts, 1)
    $lt = New-Object System.Windows.Controls.TextBlock
    $lt.Text = $opt.label; $lt.FontSize = 13; $lt.FontWeight = [System.Windows.FontWeights]::SemiBold
    $lt.Foreground = $colorTextPri; $lt.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $ts.Children.Add($lt) | Out-Null
    if ($opt.description)
    {
      $dt = New-Object System.Windows.Controls.TextBlock
      $dt.Text = $opt.description; $dt.FontSize = 11.5; $dt.Foreground = $colorTextSec
      $dt.TextWrapping = [System.Windows.TextWrapping]::Wrap
      $dt.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
      $ts.Children.Add($dt) | Out-Null
    }
    $cg.Children.Add($ts) | Out-Null; $card.Child = $cg

    $script:optionCards[$cq] += @(@{ Index = $co; Card = $card; Dot = $dot })

    # .GetNewClosure() needed here to capture loop vars $cq, $co
    $card.Add_MouseLeftButtonDown({
      $script:focusedQ = $cq; $script:focusedO[$cq] = $co
      Set-OptionSelected $cq $co; Update-OptionVisuals $cq; Update-FocusRing
    }.GetNewClosure())

    $qPanel.Children.Add($card) | Out-Null
  }

  # "Other" card
  $oc = New-Object System.Windows.Controls.Border
  $oc.Background = $colorUnselected; $oc.BorderBrush = $colorBorderNorm
  $oc.BorderThickness = [System.Windows.Thickness]::new(1.5)
  $oc.CornerRadius = [System.Windows.CornerRadius]::new(8)
  $oc.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
  $oc.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
  $oc.Cursor = [System.Windows.Input.Cursors]::Hand

  $og = New-Object System.Windows.Controls.Grid
  $oc0 = New-Object System.Windows.Controls.ColumnDefinition; $oc0.Width = [System.Windows.GridLength]::new(22)
  $oc1 = New-Object System.Windows.Controls.ColumnDefinition; $oc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
  $og.ColumnDefinitions.Add($oc0); $og.ColumnDefinitions.Add($oc1)

  $od = New-Object System.Windows.Controls.TextBlock
  $od.Text = if ($q.multiSelect) { [char]0x2610 } else { [char]0x25CB }
  $od.FontSize = 16; $od.Foreground = $colorDotEmpty
  $od.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
  $od.Margin = [System.Windows.Thickness]::new(0, 1, 0, 0)
  [System.Windows.Controls.Grid]::SetColumn($od, 0); $og.Children.Add($od) | Out-Null

  $os = New-Object System.Windows.Controls.StackPanel
  [System.Windows.Controls.Grid]::SetColumn($os, 1)
  $ol = New-Object System.Windows.Controls.TextBlock
  $ol.Text = "Other"; $ol.FontSize = 13; $ol.FontWeight = [System.Windows.FontWeights]::SemiBold
  $ol.Foreground = $colorTextPri; $os.Children.Add($ol) | Out-Null

  $ob = New-Object System.Windows.Controls.TextBox
  $ob.FontSize = 12.5; $ob.FontFamily = $monoFont
  $ob.Foreground = $colorTextPri; $ob.CaretBrush = $colorTextPri
  $ob.Background = $bc.ConvertFrom("#20000000")
  $ob.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1); $ob.BorderBrush = $colorBorderNorm
  $ob.Padding = [System.Windows.Thickness]::new(6, 4, 6, 4); $ob.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
  $ob.TextWrapping = [System.Windows.TextWrapping]::Wrap; $ob.MaxHeight = 60; $ob.AcceptsReturn = $false
  $os.Children.Add($ob) | Out-Null; $og.Children.Add($os) | Out-Null; $oc.Child = $og

  $script:optionCards[$cq] += @(@{ Index = -1; Card = $oc; Dot = $od })
  $script:otherBoxes[$cq] = $ob

  $capturedBox = $ob
  $oc.Add_MouseLeftButtonDown({
    $script:focusedQ = $cq; $script:focusedO[$cq] = -1
    Set-OptionSelected $cq (-1); Update-OptionVisuals $cq; Update-FocusRing
    $capturedBox.Focus()
  }.GetNewClosure())

  $ob.Add_TextChanged({
    if ($this.Text.Length -gt 0)
    { Set-OptionSelected $cq (-1); Update-OptionVisuals $cq }
    $script:otherTexts[$cq] = $this.Text
  }.GetNewClosure())

  $qPanel.Children.Add($oc) | Out-Null
  $questionsPanel.Children.Add($qPanel) | Out-Null
}

# ── Submit ──────────────────────────────────────────────────────────
$submitAction = {
  $lines = @(); $any = $false
  for ($qi = 0; $qi -lt $questions.Count; $qi++)
  {
    $q = $questions[$qi]
    if ($q.multiSelect)
    {
      $labels = @()
      foreach ($k in $script:selections[$qi].Keys)
      {
        if ($script:selections[$qi][$k])
        {
          if ($k -eq -1) { $v = $script:otherTexts[$qi].Trim(); if ($v) { $labels += "Other: `"$v`"" } }
          else { $labels += $q.options[$k].label }
        }
      }
      if ($labels.Count -gt 0) { $lines += "- `"$($q.question)`" -> $($labels -join ', ')"; $any = $true }
    }
    else
    {
      $s = $script:selections[$qi]
      if ($null -ne $s)
      {
        if ($s -eq -1) { $v = $script:otherTexts[$qi].Trim(); if ($v) { $lines += "- `"$($q.question)`" -> Other: `"$v`""; $any = $true } }
        else { $lines += "- `"$($q.question)`" -> $($q.options[$s].label)"; $any = $true }
      }
    }
  }
  if ($any) { $window.Tag = $lines -join "`n"; Invoke-CloseWithFade }
}

$window.FindName("SubmitBtn").Add_Click($submitAction)
$window.FindName("SkipBtn").Add_Click({ $window.Tag = "::SKIP::"; Invoke-CloseWithFade })

# ── Keyboard ────────────────────────────────────────────────────────
$window.Add_PreviewKeyDown({
  param($s, $e)
  $inTextBox = ([System.Windows.Input.FocusManager]::GetFocusedElement($window)) -is [System.Windows.Controls.TextBox]

  switch ($e.Key)
  {
    "Up"     { $e.Handled = $true; Move-Focus -1 }
    "Down"   { $e.Handled = $true; Move-Focus 1 }
    "Space"  { if (-not $inTextBox) { $e.Handled = $true; Select-FocusedOption } }
    "Tab"    {
      $e.Handled = $true
      $d = if ([System.Windows.Input.Keyboard]::Modifiers -eq "Shift") { -1 } else { 1 }
      $nq = $script:focusedQ + $d
      if ($nq -ge 0 -and $nq -lt $questions.Count)
      {
        $script:focusedQ = $nq; Update-FocusRing
        if ($script:focusedO[$nq] -eq -1 -and $script:otherBoxes.ContainsKey($nq)) { $script:otherBoxes[$nq].Focus() }
        else { $window.Focus() }
      }
    }
    "Return" {
      if (-not $inTextBox -or [System.Windows.Input.Keyboard]::Modifiers -eq "Control")
      { $e.Handled = $true; & $submitAction }
    }
    "Escape" { $window.Tag = "::SKIP::"; Invoke-CloseWithFade }
  }
})

$script:countdown = $TimeoutSeconds
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [System.TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  $script:countdown--
  $window.FindName("CountdownText").Text = "$($script:countdown)s"
  if ($script:countdown -le 0) { $timer.Stop(); $window.Tag = "::SKIP::"; Invoke-CloseWithFade }
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
  Update-FocusRing
  $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation(
    0, 1, [System.Windows.Duration]::new([System.TimeSpan]::FromMilliseconds(200)))
  $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeIn)
})

$window.ShowDialog() | Out-Null
$timer.Stop()
Write-Output $window.Tag

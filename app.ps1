# Distraction Log app: a native Windows window (no browser) with charts, goals,
# a weekly review and a Start/Stop button.
# Keep this file ASCII-only: Windows PowerShell 5.1 misreads other characters.
#   -Open today|focus|plan|plantoday|review   where to go (used by notification clicks)
param([string]$Open = '')

$ErrorActionPreference = 'Stop'
$errFile = Join-Path $PSScriptRoot 'app-error.txt'
try {

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
. (Join-Path $PSScriptRoot 'common.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FlNative {
    [DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
}
"@

# One window at a time: if already open, bring it to the front
$snap = $env:FL_SNAPSHOT   # self-test: render each tab to PNG files in this folder, then exit
$created = $false
$mutexName = $(if ($snap) { 'Local\DistractionLogAppSnapshot' } else { 'Local\DistractionLogApp' })
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
$openFile = Join-Path $PSScriptRoot 'open-request.txt'
if (-not $created) {
    # Ask the open window to go to the right place (it checks this file every second)
    if ($Open -match '^[a-z]+$') { try { Set-Content $openFile $Open -Encoding ASCII } catch {} }
    $h = [FlNative]::FindWindow([NullString]::Value, 'Distraction Log')
    if ($h -ne [IntPtr]::Zero) { [void][FlNative]::ShowWindow($h, 9); [void][FlNative]::SetForegroundWindow($h) }
    exit
}
# Own taskbar identity (matches the Start menu shortcut), so it doesn't group with PowerShell
[void][FlNative]::SetCurrentProcessExplicitAppUserModelID('DistractionLog.App')

$UP = [string][char]0x25B2; $DOWN = [string][char]0x25BC

# ---------- Colors: follow the Windows light/dark setting ----------
$light = $true
try { $light = (Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme') -ne 0 } catch {}
if ($light) {
    $P = @{ page='#f9f9f7'; surface='#fcfcfb'; ink='#0b0b0b'; ink2='#52514e'; muted='#898781'; grid='#e1e0d9'; axis='#c3c2b7'
            border='#1A0B0B0B'; focus='#2a78d6'; distract='#eb6834'; other='#c3c2b7'; wash='#0D0B0B0B'; track='#e9e8e3'; segon='#ffffff'; good='#0ca30c' }
} else {
    $P = @{ page='#0d0d0d'; surface='#1a1a19'; ink='#f0efec'; ink2='#c3c2b7'; muted='#898781'; grid='#2c2c2a'; axis='#383835'
            border='#1AFFFFFF'; focus='#3987e5'; distract='#d95926'; other='#52514e'; wash='#12FFFFFF'; track='#2c2c2a'; segon='#2c2c2a'; good='#0ca30c' }
}
$conv = New-Object System.Windows.Media.BrushConverter
$Br = @{}
foreach ($k in $P.Keys) { $b = $conv.ConvertFromString($P[$k]); $b.Freeze(); $Br[$k] = $b }
$Br['clear'] = [System.Windows.Media.Brushes]::Transparent
$Br['white'] = [System.Windows.Media.Brushes]::White

# ---------- Shared XAML pieces ----------
$legend = @'
<StackPanel Orientation="Horizontal" Margin="0,0,0,4">
  <Rectangle Width="10" Height="10" RadiusX="3" RadiusY="3" Fill="##focus##" VerticalAlignment="Center"/>
  <TextBlock Text="Focused" FontSize="12.5" Foreground="##ink2##" Margin="6,0,14,0"/>
  <Rectangle Width="10" Height="10" RadiusX="3" RadiusY="3" Fill="##distract##" VerticalAlignment="Center"/>
  <TextBlock Text="Distracting" FontSize="12.5" Foreground="##ink2##" Margin="6,0,0,0"/>
</StackPanel>
'@
$legend3 = $legend.Replace('Text="Distracting" FontSize="12.5" Foreground="##ink2##" Margin="6,0,0,0"/>',
    'Text="Distracting" FontSize="12.5" Foreground="##ink2##" Margin="6,0,14,0"/>' +
    '<Rectangle Width="10" Height="10" RadiusX="3" RadiusY="3" Fill="##other##" VerticalAlignment="Center"/>' +
    '<TextBlock Text="Neutral" FontSize="12.5" Foreground="##ink2##" Margin="6,0,0,0"/>')

$styles = @'
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="12"/><Setter Property="MinWidth" Value="12"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Border Background="Transparent">
            <Track x:Name="PART_Track" IsDirectionReversed="True" Margin="3,4">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border x:Name="t" CornerRadius="3" Background="##axis##"/>
                      <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Background" Value="##muted##"/></Trigger>
                      </ControlTemplate.Triggers>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </Border>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="##surface##"/>
      <Setter Property="BorderBrush" Value="##border##"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="16,14,16,12"/>
    </Style>
    <Style x:Key="Key" TargetType="TextBlock"><Setter Property="FontSize" Value="12.5"/><Setter Property="Foreground" Value="##ink2##"/></Style>
    <Style x:Key="Big" TargetType="TextBlock"><Setter Property="FontSize" Value="28"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,4,0,0"/><Setter Property="TextTrimming" Value="CharacterEllipsis"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock"><Setter Property="FontSize" Value="12.5"/><Setter Property="Foreground" Value="##muted##"/><Setter Property="Margin" Value="0,2,0,0"/><Setter Property="TextTrimming" Value="CharacterEllipsis"/></Style>
    <Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontSize" Value="15"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="##ink2##"/><Setter Property="FontSize" Value="13"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="b" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="6" Padding="12,4">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="##ink##"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="b" Property="Background" Value="##segon##"/>
              <Setter TargetName="b" Property="BorderBrush" Value="##border##"/>
              <Setter Property="Foreground" Value="##ink##"/>
              <Setter Property="FontWeight" Value="SemiBold"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="##ink##"/><Setter Property="Background" Value="##surface##"/>
      <Setter Property="BorderBrush" Value="##border##"/><Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="14,5">
            <ContentPresenter HorizontalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.55"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="##surface##"/><Setter Property="Foreground" Value="##ink##"/>
      <Setter Property="BorderBrush" Value="##axis##"/><Setter Property="CaretBrush" Value="##ink##"/>
      <Setter Property="Padding" Value="6,4"/><Setter Property="FontSize" Value="14"/>
    </Style>
'@

function New-Meter($name, $brush) {
@"
<Grid Height="8" Margin="0,12,0,0">
  <Border CornerRadius="4" Background="##track##"/>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition x:Name="${name}A" Width="0*"/><ColumnDefinition x:Name="${name}B" Width="1*"/></Grid.ColumnDefinitions>
    <Border CornerRadius="4" Background="##$brush##"/>
  </Grid>
</Grid>
"@
}

function Expand-Xaml([string]$x) {
    $x = $x.Replace('##styles##', $styles).Replace('##legend3##', $legend3).Replace('##legend##', $legend)
    $x = $x.Replace('##goalmeter##', (New-Meter 'Goal' 'focus')).Replace('##limitmeter##', (New-Meter 'Lim' 'distract'))
    $x = $x.Replace('##sessmeter##', (New-Meter 'Sess' 'focus'))
    foreach ($k in $P.Keys) { $x = $x.Replace("##$k##", $P[$k]) }
    return $x
}

# ---------- Main window layout ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Distraction Log" Width="1120" Height="860" MinWidth="760" MinHeight="460"
        ResizeMode="CanResize" WindowStyle="SingleBorderWindow" ShowInTaskbar="True"
        WindowStartupLocation="Manual" Background="##page##" Foreground="##ink##"
        FontFamily="Segoe UI" FontSize="14" UseLayoutRounding="True">
  <Window.Resources>
##styles##
  </Window.Resources>

  <ScrollViewer VerticalScrollBarVisibility="Auto">
    <Grid Margin="24,20,24,24" MaxWidth="1080">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0">
      <DockPanel Margin="0,0,0,14" LastChildFill="False">
        <StackPanel DockPanel.Dock="Left" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Distraction Log" FontSize="22" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <Border Margin="14,0,0,0" CornerRadius="11" BorderBrush="##border##" BorderThickness="1" Background="##surface##" Padding="8,3,10,3" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
              <Ellipse x:Name="StatusDot" Width="8" Height="8" VerticalAlignment="Center"/>
              <TextBlock x:Name="StatusText" Margin="6,0,0,0" FontSize="12.5" Foreground="##ink2##"/>
            </StackPanel>
          </Border>
          <Button x:Name="ToggleBtn" Style="{StaticResource Btn}" Margin="10,0,0,0" VerticalAlignment="Center" MinWidth="120"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Border Background="##wash##" CornerRadius="8" Padding="3" VerticalAlignment="Center" ToolTip="Language / Idioma">
            <StackPanel Orientation="Horizontal">
              <RadioButton x:Name="LEn" Style="{StaticResource Seg}" GroupName="lang" Content="EN"/>
              <RadioButton x:Name="LPt" Style="{StaticResource Seg}" GroupName="lang" Content="PT"/>
            </StackPanel>
          </Border>
          <Button x:Name="CatBtn" Style="{StaticResource Btn}" Content="Sites &amp; apps" Margin="8,0,0,0"/>
          <Button x:Name="ExportBtn" Style="{StaticResource Btn}" Content="Export" Margin="8,0,0,0" ToolTip="Save your data as CSV files for Excel"/>
          <Button x:Name="SettingsBtn" Style="{StaticResource Btn}" Content="Settings" Margin="8,0,0,0"/>
        </StackPanel>
      </DockPanel>
      <DockPanel Margin="0,0,0,14" LastChildFill="False">
        <Border DockPanel.Dock="Left" Background="##wash##" CornerRadius="8" Padding="3">
          <StackPanel Orientation="Horizontal">
            <RadioButton x:Name="VOver" Style="{StaticResource Seg}" GroupName="view" Content="Overview" IsChecked="True"/>
            <RadioButton x:Name="VDist" Style="{StaticResource Seg}" GroupName="view" Content="Distractions"/>
            <RadioButton x:Name="VSess" Style="{StaticResource Seg}" GroupName="view" Content="Sessions"/>
            <RadioButton x:Name="VPat" Style="{StaticResource Seg}" GroupName="view" Content="Patterns"/>
            <RadioButton x:Name="VRev" Style="{StaticResource Seg}" GroupName="view" Content="Weekly review"/>
          </StackPanel>
        </Border>
        <Border x:Name="RangeBox" DockPanel.Dock="Right" Background="##wash##" CornerRadius="8" Padding="3">
          <StackPanel Orientation="Horizontal">
            <RadioButton x:Name="R1" Style="{StaticResource Seg}" GroupName="range" Content="Today" IsChecked="True"/>
            <RadioButton x:Name="R7" Style="{StaticResource Seg}" GroupName="range" Content="7 days"/>
            <RadioButton x:Name="R30" Style="{StaticResource Seg}" GroupName="range" Content="30 days"/>
          </StackPanel>
        </Border>
        <TextBlock x:Name="RangeNote" DockPanel.Dock="Right" Style="{StaticResource Sub}" VerticalAlignment="Center" Margin="0,0,4,0"/>
      </DockPanel>
      </StackPanel>

      <Grid Grid.Row="1" Margin="0,0,0,12">
        <Grid.ColumnDefinitions><ColumnDefinition Width="1.25*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
        <Border Style="{StaticResource Card}"><Grid>
          <StackPanel x:Name="FIdle">
            <TextBlock Style="{StaticResource H2}" Text="Focus session"/>
            <TextBlock x:Name="FIdleSub" Style="{StaticResource Sub}" Margin="0,2,0,12" TextWrapping="Wrap" TextTrimming="None"/>
            <DockPanel>
              <Button x:Name="FStart" DockPanel.Dock="Right" Style="{StaticResource Btn}" Margin="8,0,0,0" MinWidth="130"
                      Background="##focus##" Foreground="White" BorderBrush="##focus##"/>
              <Grid>
                <TextBox x:Name="FTask" MaxLength="80" VerticalContentAlignment="Center"/>
                <TextBlock x:Name="FHint" Text="What are you working on?" Foreground="##muted##" Margin="9,0,0,0" FontSize="14"
                           VerticalAlignment="Center" IsHitTestVisible="False"/>
              </Grid>
            </DockPanel>
          </StackPanel>
          <StackPanel x:Name="FRun" Visibility="Collapsed">
            <DockPanel LastChildFill="False">
              <TextBlock x:Name="FRunKey" Style="{StaticResource H2}" DockPanel.Dock="Left"/>
              <TextBlock x:Name="FBlockNote" Style="{StaticResource Sub}" DockPanel.Dock="Right" VerticalAlignment="Center"/>
            </DockPanel>
            <DockPanel Margin="0,6,0,0">
              <Button x:Name="FStop" DockPanel.Dock="Right" Style="{StaticResource Btn}" VerticalAlignment="Center" MinWidth="100"/>
              <TextBlock x:Name="FClock" FontSize="28" FontWeight="SemiBold" DockPanel.Dock="Left"/>
              <TextBlock x:Name="FTaskText" FontSize="14" Foreground="##ink2##" VerticalAlignment="Center" Margin="14,4,12,0" TextTrimming="CharacterEllipsis"/>
            </DockPanel>
            ##sessmeter##
          </StackPanel>
        </Grid></Border>
        <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
          <DockPanel LastChildFill="False">
            <TextBlock Style="{StaticResource H2}" Text="Today's top 3" DockPanel.Dock="Left" VerticalAlignment="Center"/>
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
              <Button x:Name="PEdit" Style="{StaticResource Btn}" FontSize="12.5"/>
              <Button x:Name="PTomorrow" Style="{StaticResource Btn}" Content="Plan tomorrow" FontSize="12.5" Margin="6,0,0,0"/>
            </StackPanel>
          </DockPanel>
          <StackPanel x:Name="PList" Margin="0,10,0,0"/>
        </StackPanel></Border>
      </Grid>

      <UniformGrid Grid.Row="2" x:Name="Tiles" Columns="4" Margin="-6,0,-6,6">
        <Border Style="{StaticResource Card}" Margin="6"><StackPanel>
          <TextBlock x:Name="TGoalKey" Style="{StaticResource Key}" Text="Daily goal"/>
          <TextBlock x:Name="TGoal" Style="{StaticResource Big}"/>
          ##goalmeter##
          <TextBlock x:Name="TGoalSub" Style="{StaticResource Sub}" Margin="0,6,0,0"/>
        </StackPanel></Border>
        <Border Style="{StaticResource Card}" Margin="6"><StackPanel>
          <StackPanel Orientation="Horizontal">
            <Rectangle Width="10" Height="10" RadiusX="3" RadiusY="3" Fill="##focus##" VerticalAlignment="Center"/>
            <TextBlock Style="{StaticResource Key}" Text="Focused" Margin="6,0,0,0"/>
          </StackPanel>
          <TextBlock x:Name="TFocus" Style="{StaticResource Big}"/>
          <Grid x:Name="Meter" Height="8" Margin="0,12,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition x:Name="MeterF" Width="1*"/><ColumnDefinition x:Name="MeterX" Width="0*"/></Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="##focus##" CornerRadius="4,0,0,4"/>
            <Border Grid.Column="1" Background="##distract##" CornerRadius="0,4,4,0" Margin="2,0,0,0"/>
          </Grid>
          <TextBlock x:Name="TFocusSub" Style="{StaticResource Sub}" Margin="0,6,0,0"/>
        </StackPanel></Border>
        <Border Style="{StaticResource Card}" Margin="6"><StackPanel>
          <StackPanel Orientation="Horizontal">
            <Rectangle Width="10" Height="10" RadiusX="3" RadiusY="3" Fill="##distract##" VerticalAlignment="Center"/>
            <TextBlock Style="{StaticResource Key}" Text="Distracting" Margin="6,0,0,0"/>
          </StackPanel>
          <TextBlock x:Name="TLost" Style="{StaticResource Big}"/>
          ##limitmeter##
          <TextBlock x:Name="TLostSub" Style="{StaticResource Sub}" Margin="0,6,0,0"/>
        </StackPanel></Border>
        <Border Style="{StaticResource Card}" Margin="6"><StackPanel>
          <TextBlock Style="{StaticResource Key}" Text="Top distraction"/>
          <TextBlock x:Name="TTop" Style="{StaticResource Big}" FontSize="20" Margin="0,10,0,0"/>
          <TextBlock x:Name="TTopSub" Style="{StaticResource Sub}" Margin="0,14,0,0"/>
        </StackPanel></Border>
      </UniformGrid>

      <Grid Grid.Row="3" x:Name="Overview" Margin="0,0,0,12">
        <Grid.ColumnDefinitions><ColumnDefinition Width="1.25*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
        <Border Style="{StaticResource Card}"><StackPanel>
          <TextBlock Style="{StaticResource H2}" Text="When you lose focus"/>
          <TextBlock x:Name="HourSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
          ##legend##
          <Canvas x:Name="HourCanvas" Height="200" Margin="0,8,0,0"/>
        </StackPanel></Border>
        <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
          <TextBlock Style="{StaticResource H2}" Text="Where your time went"/>
          <TextBlock Style="{StaticResource Sub}" Text="Top apps and sites - change categories under Sites &amp; apps" Margin="0,2,0,10"/>
          ##legend3##
          <StackPanel x:Name="TopList" Margin="0,8,0,0"/>
        </StackPanel></Border>
      </Grid>

      <StackPanel Grid.Row="3" x:Name="ReviewPanel" Visibility="Collapsed">
        <Border Style="{StaticResource Card}" Margin="0,0,0,12"><StackPanel>
          <DockPanel LastChildFill="False">
            <TextBlock Style="{StaticResource H2}" Text="Weekly review" DockPanel.Dock="Left" VerticalAlignment="Center"/>
            <Button x:Name="CoachBtn" Style="{StaticResource Btn}" Content="Ask Claude coach" DockPanel.Dock="Right"
                    Background="##focus##" Foreground="White" BorderBrush="##focus##"
                    ToolTip="Opens Claude in Windows Terminal with a summary of your last 14 days"/>
          </DockPanel>
          <TextBlock x:Name="ReviewSub" Style="{StaticResource Sub}" Margin="0,2,0,12"/>
          <UniformGrid x:Name="ReviewStats" Columns="4"/>
        </StackPanel></Border>
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="1*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}"><StackPanel>
            <DockPanel LastChildFill="False">
              <TextBlock Style="{StaticResource H2}" Text="This week's 3 goals" DockPanel.Dock="Left" VerticalAlignment="Center"/>
              <Button x:Name="WEdit" Style="{StaticResource Btn}" FontSize="12.5" DockPanel.Dock="Right"/>
            </DockPanel>
            <TextBlock x:Name="WSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
            <StackPanel x:Name="WGoals"/>
          </StackPanel></Border>
          <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="Last week's goals"/>
            <TextBlock x:Name="WLastSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
            <StackPanel x:Name="WLast"/>
          </StackPanel></Border>
        </Grid>
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="1*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="Highlights"/>
            <StackPanel x:Name="Highlights" Margin="0,10,0,0"/>
          </StackPanel></Border>
          <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="Suggestions"/>
            <StackPanel x:Name="Tips" Margin="0,10,0,0"/>
          </StackPanel></Border>
        </Grid>
        <Border Style="{StaticResource Card}"><StackPanel>
          <TextBlock Style="{StaticResource H2}" Text="Each day vs your goal"/>
          <TextBlock x:Name="ReviewChartSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
          ##legend##
          <Canvas x:Name="ReviewCanvas" Height="200" Margin="0,8,0,0"/>
        </StackPanel></Border>
      </StackPanel>

      <StackPanel Grid.Row="3" x:Name="DistPanel" Visibility="Collapsed">
        <UniformGrid x:Name="DTiles" Columns="4" Margin="-6,0,-6,6"/>
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="1.4*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="Each distraction"/>
            <TextBlock x:Name="DListSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
            <StackPanel x:Name="DList"/>
          </StackPanel></Border>
          <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="What pulls you away"/>
            <TextBlock Style="{StaticResource Sub}" Text="The app you were in right before a distraction" Margin="0,2,0,10"/>
            <StackPanel x:Name="DFrom"/>
          </StackPanel></Border>
        </Grid>
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="1*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="When distractions start"/>
            <TextBlock x:Name="DHourSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
            <Canvas x:Name="DHourCanvas" Height="200" Margin="0,8,0,0"/>
          </StackPanel></Border>
          <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
            <TextBlock x:Name="DTrendTitle" Style="{StaticResource H2}"/>
            <TextBlock x:Name="DTrendSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
            <Canvas x:Name="DTrendCanvas" Height="200" Margin="0,8,0,0"/>
          </StackPanel></Border>
        </Grid>
      </StackPanel>

      <StackPanel Grid.Row="3" x:Name="SessPanel" Visibility="Collapsed">
        <UniformGrid x:Name="STiles" Columns="4" Margin="-6,0,-6,6"/>
        <Border Style="{StaticResource Card}" Margin="0,0,0,12"><StackPanel>
          <TextBlock x:Name="SChartTitle" Style="{StaticResource H2}"/>
          <TextBlock x:Name="SChartSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
            <Rectangle Width="10" Height="10" RadiusX="3" RadiusY="3" Fill="##focus##" VerticalAlignment="Center"/>
            <TextBlock Text="Completed" FontSize="12.5" Foreground="##ink2##" Margin="6,0,14,0"/>
            <Rectangle Width="10" Height="10" RadiusX="3" RadiusY="3" Fill="##other##" VerticalAlignment="Center"/>
            <TextBlock Text="Stopped early" FontSize="12.5" Foreground="##ink2##" Margin="6,0,0,0"/>
          </StackPanel>
          <Canvas x:Name="SChart" Height="200" Margin="0,8,0,0"/>
        </StackPanel></Border>
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="1*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="By task"/>
            <TextBlock x:Name="STaskSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
            <StackPanel x:Name="STasks"/>
          </StackPanel></Border>
          <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="Recent sessions"/>
            <TextBlock Style="{StaticResource Sub}" Text="Newest first" Margin="0,2,0,10"/>
            <StackPanel x:Name="SRecent"/>
          </StackPanel></Border>
        </Grid>
      </StackPanel>

      <StackPanel Grid.Row="3" x:Name="PatPanel" Visibility="Collapsed">
        <UniformGrid x:Name="PTiles" Columns="4" Margin="-6,0,-6,6"/>
        <Border Style="{StaticResource Card}" Margin="0,0,0,12"><StackPanel>
          <TextBlock Style="{StaticResource H2}" Text="When you focus"/>
          <TextBlock Style="{StaticResource Sub}" Text="Focused time by weekday and hour, last 4 weeks added up. Stronger color means more." Margin="0,2,0,10"/>
          <Canvas x:Name="PHeatF" Height="230" Margin="0,4,0,0"/>
        </StackPanel></Border>
        <Border Style="{StaticResource Card}" Margin="0,0,0,12"><StackPanel>
          <TextBlock Style="{StaticResource H2}" Text="When you get distracted"/>
          <TextBlock Style="{StaticResource Sub}" Text="Distracting time by weekday and hour, last 4 weeks added up. Stronger color means more." Margin="0,2,0,10"/>
          <Canvas x:Name="PHeatX" Height="230" Margin="0,4,0,0"/>
        </StackPanel></Border>
        <Grid Margin="0,0,0,12">
          <Grid.ColumnDefinitions><ColumnDefinition Width="1*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
          <Border Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="Last 12 weeks"/>
            <TextBlock x:Name="PCalSub" Style="{StaticResource Sub}" Margin="0,2,0,10" TextWrapping="Wrap" TextTrimming="None"/>
            <Canvas x:Name="PCal" Height="230" Margin="0,4,0,0"/>
          </StackPanel></Border>
          <Border Grid.Column="2" Style="{StaticResource Card}"><StackPanel>
            <TextBlock Style="{StaticResource H2}" Text="App switching"/>
            <TextBlock Style="{StaticResource Sub}" Text="Switches per hour of active time, by hour of day (last 14 days). Fewer is calmer." Margin="0,2,0,10" TextWrapping="Wrap" TextTrimming="None"/>
            <Canvas x:Name="PSwitch" Height="214" Margin="0,8,0,0"/>
          </StackPanel></Border>
        </Grid>
      </StackPanel>

      <Border Grid.Row="4" x:Name="TrendCard" Style="{StaticResource Card}" Margin="0,0,0,12" Visibility="Collapsed"><StackPanel>
        <TextBlock Style="{StaticResource H2}" Text="Day by day"/>
        <TextBlock Style="{StaticResource Sub}" Text="Active time per day; the dashed line is your daily goal" Margin="0,2,0,10"/>
        ##legend##
        <Canvas x:Name="TrendCanvas" Height="200" Margin="0,8,0,0"/>
      </StackPanel></Border>

      <Border Grid.Row="5" x:Name="SessCard" Style="{StaticResource Card}" Margin="0,0,0,12"><StackPanel>
        <TextBlock Style="{StaticResource H2}" Text="What you worked on"/>
        <TextBlock x:Name="SessSub" Style="{StaticResource Sub}" Margin="0,2,0,10"/>
        <StackPanel x:Name="SessList"/>
      </StackPanel></Border>

      <TextBlock Grid.Row="6" x:Name="Foot" FontSize="12" Foreground="##muted##" Margin="0,4,0,0"/>
    </Grid>
  </ScrollViewer>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse((Expand-Xaml $xaml))

foreach ($n in 'StatusDot','StatusText','ToggleBtn','R1','R7','R30','LEn','LPt','VOver','VDist','VSess','VPat','VRev','RangeBox','RangeNote','CatBtn','ExportBtn','SettingsBtn','Tiles',
               'DistPanel','DTiles','DListSub','DList','DFrom','DHourSub','DHourCanvas','DTrendTitle','DTrendSub','DTrendCanvas',
               'SessPanel','STiles','SChartTitle','SChartSub','SChart','STaskSub','STasks','SRecent',
               'PatPanel','PTiles','PHeatF','PHeatX','PCalSub','PCal','PSwitch',
               'FIdle','FIdleSub','FStart','FTask','FHint','FRun','FRunKey','FBlockNote','FStop','FClock','FTaskText','SessA','SessB',
               'PEdit','PTomorrow','PList','CoachBtn','WEdit','WSub','WGoals','WLastSub','WLast','SessCard','SessSub','SessList',
               'TGoalKey','TGoal','GoalA','GoalB','TGoalSub','TFocus','Meter','MeterF','MeterX','TFocusSub',
               'TLost','LimA','LimB','TLostSub','TTop','TTopSub','Overview','HourSub','HourCanvas','TopList',
               'ReviewPanel','ReviewSub','ReviewStats','Highlights','Tips','ReviewChartSub','ReviewCanvas',
               'TrendCard','TrendCanvas','Foot') {
    Set-Variable -Name $n -Value $win.FindName($n) -Scope Script
}

# ---------- Language (English / Portuguese) ----------
# Texts are written in English; after each redraw every visible text is passed through
# Tr (common.ps1, using pt.json). The original English is remembered so switching back works.
$script:TrText  = New-Object 'System.Runtime.CompilerServices.ConditionalWeakTable[object,object]'
$script:TrTip   = New-Object 'System.Runtime.CompilerServices.ConditionalWeakTable[object,object]'
$script:TrTitle = New-Object 'System.Runtime.CompilerServices.ConditionalWeakTable[object,object]'
$script:NeedRestore = $false

function Set-AppCulture {
    $ci = [Globalization.CultureInfo]::GetCultureInfo($(if ($LangCode -eq 'pt') { 'pt-BR' } else { 'en-US' }))
    [Threading.Thread]::CurrentThread.CurrentCulture = $ci
    [Threading.Thread]::CurrentThread.CurrentUICulture = $ci
}

function Get-Translated($table, $el, [string]$cur) {
    $memo = $null; $src = $cur
    if ($table.TryGetValue($el, [ref]$memo)) { if ($cur -ceq $memo[1]) { $src = $memo[0] }; [void]$table.Remove($el) }
    $new = Tr $src
    $table.Add($el, @($src, $new))
    return $new
}

function Translate-Tree($node) {
    if ($LangCode -ne 'pt' -and -not $script:NeedRestore) { return }
    Translate-Node $node
}

function Translate-Node($node) {
    if ($null -eq $node) { return }
    if ($node -is [System.Windows.FrameworkElement] -and $node.Tag -is [string] -and $node.Tag -ceq 'raw') { return }   # your own text (tasks, plans)
    if ($node -is [System.Windows.Controls.TextBlock]) {
        foreach ($in in @($node.Inlines)) {
            if ($in -is [System.Windows.Documents.Run] -and $in.Text -and -not ($in.Tag -is [string] -and $in.Tag -ceq 'raw')) {
                $n = Get-Translated $script:TrText $in $in.Text
                if ($n -cne $in.Text) { $in.Text = $n }
            }
        }
    } elseif ($node -is [System.Windows.Controls.ContentControl] -and $node.Content -is [string] -and $node.Content) {
        $n = Get-Translated $script:TrText $node ([string]$node.Content)
        if ($n -cne $node.Content) { $node.Content = $n }
    }
    if ($node -is [System.Windows.Window] -and $node.Title) {
        $n = Get-Translated $script:TrTitle $node $node.Title
        if ($n -cne $node.Title) { $node.Title = $n }
    }
    if ($node -is [System.Windows.FrameworkElement]) {
        $tt = $node.ToolTip
        if ($tt -is [string]) { $n = Get-Translated $script:TrTip $node $tt; if ($n -cne $tt) { $node.ToolTip = $n } }
        elseif ($tt -is [System.Windows.DependencyObject]) { Translate-Node $tt }
    }
    if ($node -is [System.Windows.FrameworkElement]) {
        foreach ($c in [System.Windows.LogicalTreeHelper]::GetChildren($node)) { if ($c -is [System.Windows.FrameworkElement]) { Translate-Node $c } }
    }
}

function Set-AppLanguage([string]$code) {
    if ($code -eq $LangCode) { return }
    $s = Get-FocusSettings; $s.Language = $code; Save-FocusSettings $s
    Set-FocusLanguage $code
    Set-AppCulture
    $script:NeedRestore = ($code -ne 'pt')   # switching back to English: restore the original texts
    Render
    $script:NeedRestore = $false
}

Set-AppCulture
if ($LangCode -eq 'pt') { $LPt.IsChecked = $true } else { $LEn.IsChecked = $true }

# ---------- Window size and position ----------
# Fit the screen (so the title bar and its buttons are always reachable) and remember the last placement.
$placeFile = Join-Path $PSScriptRoot 'window.json'
$wa = [System.Windows.SystemParameters]::WorkArea
$win.Width  = [math]::Min(1120, $wa.Width - 40)
$win.Height = [math]::Min(860,  $wa.Height - 40)
$win.Left   = $wa.Left + ($wa.Width - $win.Width) / 2
$win.Top    = $wa.Top + ($wa.Height - $win.Height) / 2
$startMax = $false
try {
    if (Test-Path $placeFile) {
        $pl = Get-Content $placeFile -Raw | ConvertFrom-Json
        $vl = [System.Windows.SystemParameters]::VirtualScreenLeft;  $vt = [System.Windows.SystemParameters]::VirtualScreenTop
        $vw = [System.Windows.SystemParameters]::VirtualScreenWidth; $vh = [System.Windows.SystemParameters]::VirtualScreenHeight
        if ($pl.Width -ge 760 -and $pl.Height -ge 460 -and $pl.Left -ge $vl - 8 -and $pl.Top -ge $vt -and
            ($pl.Left + 200) -le ($vl + $vw) -and ($pl.Top + 40) -le ($vt + $vh)) {
            $win.Left = $pl.Left; $win.Top = $pl.Top
            $win.Width = [math]::Min($pl.Width, $vw); $win.Height = [math]::Min($pl.Height, $vh)
        }
        $startMax = [bool]$pl.Maximized
    }
} catch {}
if ($startMax) { $win.WindowState = 'Maximized' }

$win.Add_Closing({
    if ($snap) { return }
    try {
        $b = $win.RestoreBounds
        if ($b.IsEmpty) { $b = New-Object System.Windows.Rect $win.Left, $win.Top, $win.Width, $win.Height }
        [pscustomobject]@{ Left = $b.Left; Top = $b.Top; Width = $b.Width; Height = $b.Height
                           Maximized = ($win.WindowState -eq 'Maximized') } |
            ConvertTo-Json | Set-Content $placeFile -Encoding UTF8
    } catch {}
})

$icon = Join-Path $PSScriptRoot 'app.ico'
if (Test-Path $icon) { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$icon) }

function Set-DarkTitle($w) {
    if (-not $light) {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $w).Handle
        $one = 1
        [void][FlNative]::DwmSetWindowAttribute($hwnd, 20, [ref]$one, 4)
    }
}
$win.Add_SourceInitialized({ Set-DarkTitle $win })

# ---------- Data ----------
function Reset-DataCache {
    $script:LabelCache = @{}   # "app<tab>title" -> @(label, category)
    $script:Bad        = @{}   # labels that are distracting
    $script:Neu        = @{}   # labels that are neutral (neither focused nor distracting)
    $script:DayCache   = @{}   # past days never change, so read them once
}
Reset-DataCache

# One day: Agg ("hour|label" -> seconds) and Segs (each logged piece: start second of day, seconds, label)
function Read-Day([string]$date) {
    $agg  = @{}
    $segs = New-Object System.Collections.Generic.List[object]
    $out  = [pscustomobject]@{ Agg = $agg; Segs = $segs }
    $file = Join-Path $FocusDir "logs\$date.tsv"
    if (-not (Test-Path $file)) { return $out }
    try {
        # Share read/write so the tracker can keep writing while we read
        $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd(); $sr.Close()
    } catch { return $out }
    foreach ($line in ($text -split "`r?`n")) {
        $c = $line -split "`t"
        if ($c.Count -lt 4 -or $c[0].Length -lt 13) { continue }
        $key = $c[2] + "`t" + $c[3]
        if (-not $script:LabelCache.ContainsKey($key)) {
            $l = Get-FocusLabel $c[2] $c[3]
            $script:LabelCache[$key] = @($l, (Get-FocusCategory $l $c[3]))
        }
        $info = $script:LabelCache[$key]
        if ($info[1] -eq 'distract') { $script:Bad[$info[0]] = $true }
        elseif ($info[1] -eq 'neutral') { $script:Neu[$info[0]] = $true }
        $k = [string][int]$c[0].Substring(11, 2) + '|' + $info[0]
        $agg[$k] = [int]$agg[$k] + [int]$c[1]
        if ($c[0].Length -ge 19) {
            $sod = 3600 * [int]$c[0].Substring(11, 2) + 60 * [int]$c[0].Substring(14, 2) + [int]$c[0].Substring(17, 2)
            $segs.Add(@($sod, [int]$c[1], $info[0]))
        }
    }
    return $out
}

# Last N days, oldest first: Date, Agg ("hour|label" -> seconds)
function Get-Days([int]$n, [int]$skip = 0) {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    for ($i = $n - 1 + $skip; $i -ge $skip; $i--) {
        $d = (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
        if ($d -eq $today) { $r = Read-Day $d }
        else {
            if (-not $script:DayCache.ContainsKey($d)) { $script:DayCache[$d] = Read-Day $d }
            $r = $script:DayCache[$d]
        }
        [pscustomobject]@{ Date = $d; Agg = $r.Agg; Segs = $r.Segs }
    }
}

# Totals for a list of days
function Get-Summary($days) {
    $s = [pscustomobject]@{ Total = 0; Lost = 0; Focus = 0; HourF = (New-Object 'double[]' 24); HourX = (New-Object 'double[]' 24)
                            ByLabel = @{}; PerDay = @() }
    foreach ($d in $days) {
        $df = 0; $dx = 0
        foreach ($k in $d.Agg.Keys) {
            $parts = $k.Split('|', 2); $h = [int]$parts[0]; $l = $parts[1]; $sec = $d.Agg[$k]
            $s.ByLabel[$l] = [int]$s.ByLabel[$l] + $sec
            if ($script:Bad.ContainsKey($l)) { $s.HourX[$h] += $sec; $dx += $sec }
            elseif (-not $script:Neu.ContainsKey($l)) { $s.HourF[$h] += $sec; $df += $sec }
        }
        $s.PerDay += [pscustomobject]@{ Date = $d.Date; F = $df; X = $dx }
        $s.Focus += $df; $s.Lost += $dx
    }
    $s.Total = $s.Focus + $s.Lost
    return $s
}

function Format-Time($s) { Format-FocusTime $s }
function Format-Hours($min) { if ($min % 60 -eq 0) { '{0}h' -f ($min / 60) } else { Format-FocusTime ($min * 60) } }

# ---------- Drawing helpers ----------
function N($v) { [string][math]::Round([double]$v, 2) }   # invariant number text for geometry

function Add-Text($canvas, $text, $x, $y, $w, $align) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text; $tb.FontSize = 11; $tb.Foreground = $Br.muted; $tb.Width = $w; $tb.TextAlignment = $align
    [System.Windows.Controls.Canvas]::SetLeft($tb, $x); [System.Windows.Controls.Canvas]::SetTop($tb, $y)
    [void]$canvas.Children.Add($tb)
}

# Series spec for bar charts: names, colors and whether values are counts (default: focused/distracting time)
function New-Spec($a = 'Focused', $ab = $null, $b = 'Distracting', $bb = $null, [switch]$Count) {
    if (-not $ab) { $ab = $Br.focus }
    if ($b -and -not $bb) { $bb = $Br.distract }
    @{ A = $a; AB = $ab; B = $b; BB = $bb; Count = [bool]$Count }
}
$script:TimeSpec = $null

function Format-Value($v, $spec) { if ($spec.Count) { [string][int]$v } else { Format-Time $v } }

function New-Tip($title, $f, $x, $extra, $spec) {
    if (-not $spec) { $spec = New-Spec }
    $sp = New-Object System.Windows.Controls.StackPanel
    $h = New-Object System.Windows.Controls.TextBlock; $h.Text = $title; $h.FontWeight = 'SemiBold'; $h.Margin = '0,0,0,4'
    [void]$sp.Children.Add($h)
    $rows = @(, @($spec.A, $f, $spec.AB))
    if ($spec.B) { $rows += , @($spec.B, $x, $spec.BB) }
    foreach ($row in $rows) {
        $d = New-Object System.Windows.Controls.DockPanel; $d.Margin = '0,1,0,1'
        $sw = New-Object System.Windows.Shapes.Rectangle; $sw.Width = 10; $sw.Height = 10; $sw.RadiusX = 3; $sw.RadiusY = 3; $sw.Fill = $row[2]
        $sw.Margin = '0,0,6,0'; [System.Windows.Controls.DockPanel]::SetDock($sw, 'Left')
        $v = New-Object System.Windows.Controls.TextBlock; $v.Text = (Format-Value $row[1] $spec); $v.Margin = '16,0,0,0'
        [System.Windows.Controls.DockPanel]::SetDock($v, 'Right')
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $row[0]
        [void]$d.Children.Add($sw); [void]$d.Children.Add($v); [void]$d.Children.Add($t)
        [void]$sp.Children.Add($d)
    }
    if ($extra) { $e = New-Object System.Windows.Controls.TextBlock; $e.Text = $extra; $e.Margin = '0,4,0,0'; [void]$sp.Children.Add($e) }
    return $sp
}

function New-TopRounded($x, $y, $w, $h) {
    $r = [math]::Min(4, [math]::Min($w / 2, $h))
    $d = "M$(N $x),$(N ($y + $h)) V$(N ($y + $r)) Q$(N $x),$(N $y) $(N ($x + $r)),$(N $y) H$(N ($x + $w - $r)) Q$(N ($x + $w)),$(N $y) $(N ($x + $w)),$(N ($y + $r)) V$(N ($y + $h)) Z"
    $p = New-Object System.Windows.Shapes.Path
    $p.Data = [System.Windows.Media.Geometry]::Parse($d)
    return $p
}

# Stacked bars: focused at the bottom, distracting on top, 2px gap, rounded top ends.
# $goalSec > 0 draws a dashed goal line (compared against the focused part).
function Draw-Stack($canvas, $cats, [int]$labelEvery, [double]$goalSec = 0, $spec = $null) {
    $canvas.Children.Clear()
    if (-not $cats) { return }
    if (-not $spec) { $spec = New-Spec }
    $unit = $(if ($spec.Count) { 1 } else { 60 })   # time is drawn in minutes
    $W = [math]::Max(280, $canvas.ActualWidth); $H = $canvas.Height
    $mt = 8; $mr = 4; $mb = 24; $ml = 48
    $iw = $W - $ml - $mr; $ih = $H - $mt - $mb; $base = $mt + $ih
    $maxV = [math]::Max(1, $goalSec / 60)
    foreach ($c in $cats) { $maxV = [math]::Max($maxV, ($c.F + $c.X) / $unit) }
    $steps = $(if ($spec.Count) { @(1, 2, 5, 10, 20, 50, 100, 200, 500) } else { @(5, 10, 15, 30, 60, 120, 180, 240, 360, 480, 600, 720) })
    $step = $steps[-1] * 2
    foreach ($s in $steps) { if ($maxV / $s -le 4) { $step = $s; break } }
    $top = [math]::Ceiling($maxV / $step) * $step

    for ($v = 0; $v -le $top; $v += $step) {
        $yy = $base - $ih * $v / $top
        $ln = New-Object System.Windows.Shapes.Line
        $ln.X1 = $ml; $ln.X2 = $W - $mr; $ln.Y1 = $yy; $ln.Y2 = $yy; $ln.StrokeThickness = 1
        $ln.Stroke = $(if ($v -eq 0) { $Br.axis } else { $Br.grid })
        [void]$canvas.Children.Add($ln)
        $axisText = $(if ($spec.Count) { [string]$v } elseif ($v -ge 60 -and $v % 60 -eq 0) { "$($v / 60)h" } else { Format-Time ($v * 60) })
        Add-Text $canvas $axisText 0 ($yy - 8) ($ml - 8) 'Right'
    }

    $band = $iw / $cats.Count
    $bw = [math]::Max(3, [math]::Min(30, $band * 0.62))
    for ($i = 0; $i -lt $cats.Count; $i++) {
        $c = $cats[$i]
        $x = $ml + $i * $band + ($band - $bw) / 2
        $hf = $ih * ($c.F / $unit) / $top; $hx = $ih * ($c.X / $unit) / $top
        $gap = $(if ($hf -gt 0 -and $hx -gt 0) { 2 } else { 0 })
        if ($hf -gt 0) {
            if ($hx -gt 0) { $shape = New-Object System.Windows.Shapes.Rectangle; $shape.Width = $bw; $shape.Height = $hf
                             [System.Windows.Controls.Canvas]::SetLeft($shape, $x); [System.Windows.Controls.Canvas]::SetTop($shape, $base - $hf) }
            else { $shape = New-TopRounded $x ($base - $hf) $bw $hf }
            $shape.Fill = $spec.AB; [void]$canvas.Children.Add($shape)
        }
        if ($hx -gt 0) {
            $shape = New-TopRounded $x ($base - $hf - $gap - $hx) $bw $hx
            $shape.Fill = $spec.BB; [void]$canvas.Children.Add($shape)
        }
        if ($i % $labelEvery -eq 0) { Add-Text $canvas $c.Label ($x + $bw / 2 - 40) ($H - 18) 80 'Center' }
    }

    if ($goalSec -gt 0) {
        $gy = $base - $ih * ($goalSec / 60) / $top
        $gl = New-Object System.Windows.Shapes.Line
        $gl.X1 = $ml; $gl.X2 = $W - $mr; $gl.Y1 = $gy; $gl.Y2 = $gy; $gl.StrokeThickness = 1.5
        $gl.Stroke = $Br.ink2; $gl.StrokeDashArray = [System.Windows.Media.DoubleCollection]::Parse('4 3')
        [void]$canvas.Children.Add($gl)
        $gt = New-Object System.Windows.Controls.TextBlock; $gt.Text = $(if ($spec.GoalName) { $spec.GoalName } else { 'Goal' }); $gt.FontSize = 11; $gt.Foreground = $Br.ink2
        $gt.Background = $Br.surface; $gt.Padding = '4,0,4,0'
        [System.Windows.Controls.Canvas]::SetRight($gt, $mr); [System.Windows.Controls.Canvas]::SetTop($gt, $gy - 16)
        [void]$canvas.Children.Add($gt)
    }

    # Hover targets on top of everything
    for ($i = 0; $i -lt $cats.Count; $i++) {
        $c = $cats[$i]
        $hit = New-Object System.Windows.Shapes.Rectangle
        $hit.Width = $band; $hit.Height = $ih; $hit.RadiusX = 4; $hit.RadiusY = 4; $hit.Fill = $Br.clear
        [System.Windows.Controls.Canvas]::SetLeft($hit, $ml + $i * $band); [System.Windows.Controls.Canvas]::SetTop($hit, $mt)
        $extra = $null
        if ($goalSec -gt 0) { $extra = $(if ($c.F -ge $goalSec) { 'Goal met' } else { 'Goal not met (' + (Format-Time ($goalSec - $c.F)) + ' short)' }) }
        if ($c.Extra) { $extra = $c.Extra }
        $hit.ToolTip = New-Tip $c.Tip $c.F $c.X $extra $spec
        [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($hit, 0)
        $hit.Add_MouseEnter({ $this.Fill = $Br.wash })
        $hit.Add_MouseLeave({ $this.Fill = $Br.clear })
        [void]$canvas.Children.Add($hit)
    }
    Translate-Tree $canvas
}

function New-TopRow($label, $secs, $max, $total, $brush) {
    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = '0,0,0,9'; $g.Background = $Br.clear
    $g.ToolTip = '{0}: {1} ({2}%)' -f $label, (Format-Time $secs), [int](100 * $secs / [math]::Max(1, $total))
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition)); $g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))

    $name = New-Object System.Windows.Controls.DockPanel
    $sw = New-Object System.Windows.Shapes.Rectangle; $sw.Width = 10; $sw.Height = 10; $sw.RadiusX = 3; $sw.RadiusY = 3; $sw.Fill = $brush
    $sw.Margin = '0,0,8,0'; $sw.VerticalAlignment = 'Center'; [System.Windows.Controls.DockPanel]::SetDock($sw, 'Left')
    $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = $label; $tb.FontSize = 13; $tb.FontWeight = 'Medium'; $tb.TextTrimming = 'CharacterEllipsis'
    [void]$name.Children.Add($sw); [void]$name.Children.Add($tb)
    [void]$g.Children.Add($name)

    $t = New-Object System.Windows.Controls.TextBlock; $t.Text = (Format-Time $secs); $t.FontSize = 13; $t.Foreground = $Br.ink2; $t.Margin = '12,0,0,0'
    [System.Windows.Controls.Grid]::SetColumn($t, 1); [void]$g.Children.Add($t)

    $bar = New-Object System.Windows.Controls.Grid; $bar.Margin = '0,5,0,0'
    $a = New-Object System.Windows.Controls.ColumnDefinition; $a.Width = New-Object System.Windows.GridLength ([math]::Max(0.01, $secs)), 'Star'
    $b = New-Object System.Windows.Controls.ColumnDefinition; $b.Width = New-Object System.Windows.GridLength ([math]::Max(0, $max - $secs)), 'Star'
    $bar.ColumnDefinitions.Add($a); $bar.ColumnDefinitions.Add($b)
    $fill = New-Object System.Windows.Controls.Border; $fill.Height = 6; $fill.CornerRadius = '0,3,3,0'; $fill.Background = $brush; $fill.MinWidth = 2
    [void]$bar.Children.Add($fill)
    [System.Windows.Controls.Grid]::SetRow($bar, 1); [System.Windows.Controls.Grid]::SetColumnSpan($bar, 2)
    [void]$g.Children.Add($bar)
    return $g
}

function Set-Meter($colA, $colB, [double]$fraction) {
    $f = [math]::Max(0.0, [math]::Min(1.0, $fraction))   # 0.0/1.0: integer literals would round the fraction down
    $colA.Width = New-Object System.Windows.GridLength $f, 'Star'
    $colB.Width = New-Object System.Windows.GridLength (1 - $f), 'Star'
}

function New-Line($text, [string]$strong) {
    # A text line with an optional bold lead-in
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,0,0,10'; $tb.FontSize = 13.5; $tb.Foreground = $Br.ink
    if ($strong) { $r = New-Object System.Windows.Documents.Run $strong; $r.FontWeight = 'SemiBold'; [void]$tb.Inlines.Add($r) }
    $r2 = New-Object System.Windows.Documents.Run $text; $r2.Foreground = $Br.ink2; [void]$tb.Inlines.Add($r2)
    return $tb
}

function New-Stat($key, $value, $delta) {
    $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = '0,0,16,4'
    $k = New-Object System.Windows.Controls.TextBlock; $k.Text = $key; $k.FontSize = 12.5; $k.Foreground = $Br.ink2
    $v = New-Object System.Windows.Controls.TextBlock; $v.Text = $value; $v.FontSize = 24; $v.FontWeight = 'SemiBold'; $v.Margin = '0,2,0,0'
    $d = New-Object System.Windows.Controls.TextBlock; $d.Text = $delta; $d.FontSize = 12.5; $d.Foreground = $Br.muted; $d.Margin = '0,2,0,0'
    [void]$sp.Children.Add($k); [void]$sp.Children.Add($v); [void]$sp.Children.Add($d)
    return $sp
}

function Get-Delta($now, $before, [switch]$Percent) {
    if ($Percent) {
        $diff = [int]($now - $before)
        if ($diff -eq 0) { return 'Same as the week before' }
        $arrow = $(if ($diff -gt 0) { $UP } else { $DOWN })
        return "$arrow $([math]::Abs($diff)) pts vs the week before"
    }
    if ($before -le 0) { return $(if ($now -gt 0) { 'No data the week before' } else { '' }) }
    $pct = [int][math]::Round(100 * ($now - $before) / $before)
    if ($pct -eq 0) { return 'Same as the week before' }
    $arrow = $(if ($pct -gt 0) { $UP } else { $DOWN })
    return "$arrow $([math]::Abs($pct))% vs the week before"
}

# ---------- Focus timer, plans and sessions ----------
function Test-Blocker { Test-Path (Join-Path $env:ProgramData 'DistractionLog\blocker.ps1') }
$script:HasBlocker = Test-Blocker
$script:IdleSubText = ''

function Format-Clock([double]$secs) {
    $t = [int][math]::Max(0, [math]::Ceiling($secs))
    '{0}:{1:00}' -f [int][math]::Floor($t / 60), ($t % 60)
}

function Render-FocusBar($s) {
    if (-not $s) { $s = Get-FocusSession }
    $set = $script:Settings; $now = Get-Date
    if ($s.State -eq 'focus' -or $s.State -eq 'break') {
        $FIdle.Visibility = 'Collapsed'; $FRun.Visibility = 'Visible'
        if ($s.State -eq 'focus') {
            $st = ConvertTo-FocusDate $s.Start; $en = ConvertTo-FocusDate $s.End
            $FRunKey.Text = 'Focus session'
            $FTaskText.Text = $(if ($s.Task) { $s.Task } else { 'Stay on one task until the timer ends' }); $FTaskText.Tag = $(if ($s.Task) { 'raw' } else { $null })
            $FStop.Content = 'Stop'
            $FBlockNote.Text = $(if ($script:HasBlocker -and $set.BlockDuringFocus) { 'Distracting sites are blocked' } else { '' })
        } else {
            $en = ConvertTo-FocusDate $s.BreakEnd; $st = $en.AddMinutes(-[math]::Max(1, [int]$set.BreakMinutes))
            $FRunKey.Text = 'Break'
            $FTaskText.Text = 'Stand up, stretch, look away from the screen'; $FTaskText.Tag = $null
            $FStop.Content = 'Skip break'
            $FBlockNote.Text = ''
        }
        $FClock.Text = (Format-Clock ($en - $now).TotalSeconds) + ' left'
        Set-Meter $SessA $SessB (($now - $st).TotalSeconds / [math]::Max(1, ($en - $st).TotalSeconds))
    } else {
        $FIdle.Visibility = 'Visible'; $FRun.Visibility = 'Collapsed'
        $FStart.Content = 'Start ' + [int]$set.SessionMinutes + ' min'
        $FIdleSub.Text = $script:IdleSubText
    }
    Translate-Tree $FIdle.Parent
}

function Start-Focus {
    Start-FocusSession $FTask.Text ([int]$script:Settings.SessionMinutes)
    $script:LastState = 'focus'
    Render-FocusBar
}

function Get-PlanCount($p) {
    $n = 0; $d = 0
    for ($i = 0; $i -lt 3; $i++) { if ($p.Items[$i]) { $n++; if ($p.Done[$i]) { $d++ } } }
    return @($n, $d)
}

function Set-PlanStyle($cb) {
    $tb = $cb.Content
    if ($cb.IsChecked) { $tb.TextDecorations = [System.Windows.TextDecorations]::Strikethrough; $tb.Foreground = $Br.muted }
    else { $tb.TextDecorations = $null; $tb.Foreground = $Br.ink }
}

$script:ShowDone = @{}   # plan key -> $true while you chose to see the done items
$CHECK = [string][char]0x2713

function Update-Plans { if ($script:View -eq 'review') { Render } else { Render-Plan } }

# Fills a panel with check boxes for a plan; returns $true when the plan has items.
# -HideDone: checked items fade out and are kept under a small "done - show" link.
function Add-PlanList($panel, [string]$key, [string]$empty, [switch]$HideDone, [string]$allDone = 'All done. Nice work!') {
    $panel.Children.Clear()
    $p = Get-FocusPlan $key
    if (-not (Test-FocusPlan $p)) {
        $e = New-Object System.Windows.Controls.TextBlock; $e.Text = $empty; $e.Foreground = $Br.muted; $e.TextWrapping = 'Wrap'; $e.FontSize = 13.5
        [void]$panel.Children.Add($e)
        return $false
    }
    $c = Get-PlanCount $p
    $hiding = $HideDone -and -not $script:ShowDone[$key]
    for ($i = 0; $i -lt 3; $i++) {
        if (-not $p.Items[$i]) { continue }
        if ($hiding -and $p.Done[$i]) { continue }
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Margin = '0,0,0,8'; $cb.VerticalContentAlignment = 'Center'; $cb.Cursor = 'Hand'
        $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = $p.Items[$i]; $tb.Tag = 'raw'; $tb.TextWrapping = 'Wrap'; $tb.FontSize = 14; $tb.Margin = '4,0,0,0'
        $cb.Content = $tb; $cb.IsChecked = [bool]$p.Done[$i]; $cb.Tag = "$key|$i|$([int][bool]$HideDone)|$([int]$hiding)"
        Set-PlanStyle $cb
        $cb.Add_Click({
            $k, $n, $hd, $hid = $this.Tag.Split('|')
            $pl = Get-FocusPlan $k; $pl.Done[[int]$n] = [bool]$this.IsChecked
            Set-FocusPlan $k $pl.Items $pl.Done
            Set-PlanStyle $this
            $op = [System.Windows.UIElement]::OpacityProperty
            if ($this.IsChecked -and $hid -eq '1') {
                # Let the tick show for a moment, then fade out and refresh the list
                $a = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, 0.0, (New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(450))))
                $a.BeginTime = [TimeSpan]::FromMilliseconds(700)
                $a.Add_Completed({ Update-Plans })
                $this.BeginAnimation($op, $a)
            } else {
                $this.BeginAnimation($op, $null); $this.Opacity = 1
                if ($hd -eq '1' -or $script:View -eq 'review') { Update-Plans }
            }
        })
        [void]$panel.Children.Add($cb)
    }
    if ($HideDone -and $c[1] -gt 0) {
        if ($hiding -and $c[1] -eq $c[0]) {
            $all = New-Object System.Windows.Controls.TextBlock; $all.Text = $allDone; $all.FontSize = 14; $all.FontWeight = 'SemiBold'
            $all.Foreground = $Br.ink; $all.Margin = '0,0,0,8'; $all.TextWrapping = 'Wrap'
            [void]$panel.Children.Add($all)
        }
        $link = New-Object System.Windows.Controls.TextBlock
        $link.Text = "$CHECK $($c[1]) done - " + $(if ($hiding) { 'show' } else { 'hide' })
        $link.FontSize = 12.5; $link.Foreground = $Br.muted; $link.Cursor = 'Hand'; $link.Tag = $key; $link.Margin = '0,2,0,0'
        $link.ToolTip = $(if ($hiding) { 'Show the items you already finished' } else { 'Hide the finished items' })
        $link.Add_MouseEnter({ $this.TextDecorations = [System.Windows.TextDecorations]::Underline })
        $link.Add_MouseLeave({ $this.TextDecorations = $null })
        $link.Add_MouseLeftButtonUp({ $script:ShowDone[$this.Tag] = -not $script:ShowDone[$this.Tag]; Update-Plans })
        [void]$panel.Children.Add($link)
    }
    return $true
}

function Render-Plan {
    $has = Add-PlanList $PList (Get-Date).ToString('yyyy-MM-dd') 'No plan yet. What 3 things would make today a good day?' -HideDone -allDone 'All done for today. Nice work!'
    $PEdit.Content = $(if ($has) { 'Edit' } else { 'Plan today' })
    $tom = Get-FocusPlan ((Get-Date).AddDays(1).ToString('yyyy-MM-dd'))
    $PTomorrow.Content = $(if (Test-FocusPlan $tom) { 'Tomorrow: planned' } else { 'Plan tomorrow' })
    Translate-Tree $PList.Parent
}

function Render-Sessions([int]$n) {
    $today = @(Get-FocusSessions 1)
    $doneToday = @($today | Where-Object Done).Count
    $secsToday = ($today | Measure-Object Secs -Sum).Sum
    $tip = $(if ($script:On) { 'If you open a distracting site during a session, you get an alert right away.' } else { 'Turn tracking on to get alerts during sessions.' })
    $script:IdleSubText = $(if ($today) { "Today: $doneToday session$(if ($doneToday -ne 1) { 's' }) completed, $(Format-Time $secsToday) in sessions. $tip" }
                             else { "Pick one task and work on it until the timer ends. $tip" })

    $all = @(Get-FocusSessions $n)
    $SessList.Children.Clear()
    $period = $(if ($n -eq 1) { 'today' } else { "in the last $n days" })
    if (-not $all) {
        $SessSub.Text = 'Your focus sessions, grouped by task'
        $e = New-Object System.Windows.Controls.TextBlock; $e.Foreground = $Br.muted; $e.TextWrapping = 'Wrap'; $e.FontSize = 13.5
        $e.Text = "No focus sessions $period yet. Type what you are working on above and press Start: each session is listed here by task."
        [void]$SessList.Children.Add($e)
        return
    }
    $groups = @($all | Group-Object { if ($_.Task) { $_.Task } else { '(no task name)' } } | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Count = $_.Count; Secs = ($_.Group | Measure-Object Secs -Sum).Sum } } | Sort-Object Secs -Descending)
    $total = ($all | Measure-Object Secs -Sum).Sum
    $SessSub.Text = "$($all.Count) session$(if ($all.Count -ne 1) { 's' }) $period, $(Format-Time $total) in total"
    foreach ($g in ($groups | Select-Object -First 8)) {
        $name = "$($g.Name)   ($($g.Count) session$(if ($g.Count -ne 1) { 's' }))"
        [void]$SessList.Children.Add((New-TopRow $name $g.Secs $groups[0].Secs $total $Br.focus))
    }
}

function Render-WeekGoals {
    $wk = Get-FocusWeekId (Get-Date); $lw = Get-FocusWeekId ((Get-Date).AddDays(-7))
    $has = Add-PlanList $WGoals $wk 'No goals for this week yet. What would make this week a success?' -HideDone -allDone 'All of this week''s goals are done!'
    $WEdit.Content = $(if ($has) { 'Edit' } else { 'Set goals' })
    $c = Get-PlanCount (Get-FocusPlan $wk)
    $WSub.Text = $(if ($has) { "$($c[1]) of $($c[0]) done - tick them off as you go" } else { 'Pick 3 concrete outcomes for the week' })
    $hasL = Add-PlanList $WLast $lw 'No goals were set last week.'
    $c = Get-PlanCount (Get-FocusPlan $lw)
    $WLastSub.Text = $(if ($hasL) { "You finished $($c[1]) of $($c[0])" } else { 'Set goals this week and you will see them here next week' })
}

# ---------- Plan dialog (daily top 3 / weekly goals) ----------
function New-PlanDialog([string]$key, [string]$title, [string]$sub, $prefill) {
    $px = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="480" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="##page##" Foreground="##ink##" FontFamily="Segoe UI" FontSize="14" UseLayoutRounding="True">
  <Window.Resources>
##styles##
  </Window.Resources>
  <StackPanel Margin="22,18,22,20">
    <TextBlock x:Name="PTitle" FontSize="18" FontWeight="SemiBold"/>
    <TextBlock x:Name="PSub" Style="{StaticResource Sub}" TextWrapping="Wrap" TextTrimming="None" Margin="0,4,0,16"/>
    <DockPanel Margin="0,0,0,10"><TextBlock Text="1" Width="22" FontWeight="SemiBold" VerticalAlignment="Center"/><TextBox x:Name="P1" MaxLength="120"/></DockPanel>
    <DockPanel Margin="0,0,0,10"><TextBlock Text="2" Width="22" FontWeight="SemiBold" VerticalAlignment="Center"/><TextBox x:Name="P2" MaxLength="120"/></DockPanel>
    <DockPanel Margin="0,0,0,10"><TextBlock Text="3" Width="22" FontWeight="SemiBold" VerticalAlignment="Center"/><TextBox x:Name="P3" MaxLength="120"/></DockPanel>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
      <Button x:Name="PCancel" Style="{StaticResource Btn}" Content="Cancel" MinWidth="90" IsCancel="True"/>
      <Button x:Name="PSave" Style="{StaticResource Btn}" Content="Save" MinWidth="90" Margin="8,0,0,0" IsDefault="True"
              Background="##focus##" Foreground="White" BorderBrush="##focus##"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse((Expand-Xaml $px))
    if ($win.Icon) { $dlg.Icon = $win.Icon }
    $dlg.Add_SourceInitialized({ Set-DarkTitle ([System.Windows.Window]$this) })
    $dlg.Title = $title
    $dlg.FindName('PTitle').Text = $title; $dlg.FindName('PSub').Text = $sub
    $old = Get-FocusPlan $key
    $fill = $(if (Test-FocusPlan $old) { $old.Items } else { @($prefill) + @('', '', '') })
    $j = 0
    foreach ($n in 'P1', 'P2', 'P3') { $dlg.FindName($n).Text = [string]$fill[$j]; $j++ }
    $dlg.Tag = @{ Key = $key; Old = $old }
    $dlg.Add_ContentRendered({ $t = ([System.Windows.Window]$this).FindName('P1'); [void]$t.Focus(); $t.CaretIndex = $t.Text.Length })
    $dlg.FindName('PSave').Add_Click({
        $d = [System.Windows.Window]::GetWindow($this)
        $items = @(foreach ($n in 'P1', 'P2', 'P3') { $d.FindName($n).Text.Trim() })
        $items = @(@(@($items | Where-Object { $_ }) + @('', '', '')) | Select-Object -First 3)   # no gaps
        $old = $d.Tag.Old
        $done = @(for ($i = 0; $i -lt 3; $i++) { $k = [array]::IndexOf($old.Items, $items[$i]); $items[$i] -and $k -ge 0 -and $old.Done[$k] })
        Set-FocusPlan $d.Tag.Key $items $done
        $d.DialogResult = $true
    })
    return $dlg
}

function Get-Undone($p) { @(for ($i = 0; $i -lt 3; $i++) { if ($p.Items[$i] -and -not $p.Done[$i]) { $p.Items[$i] } }) }

function New-DayPlanDialog([bool]$tomorrow) {
    if ($tomorrow) {
        $key = (Get-Date).AddDays(1).ToString('yyyy-MM-dd')
        $carry = Get-Undone (Get-FocusPlan (Get-Date).ToString('yyyy-MM-dd'))
        return New-PlanDialog $key ('Plan tomorrow (' + (Get-Date).AddDays(1).ToString('dddd') + ')') "The 3 things that would make tomorrow a good day. Put the hardest first and do it before email and chats. Unfinished items from today are filled in." $carry
    }
    return New-PlanDialog (Get-Date).ToString('yyyy-MM-dd') "Today's top 3" 'The 3 things that would make today a good day. Put the hardest first and do it before email and chats.' @()
}

function New-WeekPlanDialog {
    $carry = Get-Undone (Get-FocusPlan (Get-FocusWeekId ((Get-Date).AddDays(-7))))
    return New-PlanDialog (Get-FocusWeekId (Get-Date)) "This week's 3 goals" "What would make this week a success? Make them concrete, like 'Send the proposal to the client'. Unfinished goals from last week are filled in." $carry
}

function Show-Dialog($dlg) {
    $dlg.Owner = $win
    Translate-Tree $dlg
    if ($dlg.ShowDialog()) { Render }
}

# ---------- Sites & apps dialog (categories) ----------
function New-CatDialog {
    $cx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sites and apps" Width="680" Height="640" MinWidth="560" MinHeight="360" ResizeMode="CanResize"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="##page##" Foreground="##ink##" FontFamily="Segoe UI" FontSize="14" UseLayoutRounding="True">
  <Window.Resources>
##styles##
  </Window.Resources>
  <DockPanel Margin="22,18,22,20">
    <StackPanel DockPanel.Dock="Top" Margin="0,0,0,12">
      <TextBlock Text="Sites and apps" FontSize="18" FontWeight="SemiBold"/>
      <TextBlock Style="{StaticResource Sub}" TextWrapping="Wrap" TextTrimming="None" Margin="0,4,0,0"
                 Text="Choose what each one counts as. Work = focused time. Neutral = counted as neither (music, system screens). Distracting = counts toward your limit and alerts. Showing the last 14 days."/>
    </StackPanel>
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="CCancel" Style="{StaticResource Btn}" Content="Cancel" MinWidth="90" IsCancel="True"/>
      <Button x:Name="CSave" Style="{StaticResource Btn}" Content="Save" MinWidth="90" Margin="8,0,0,0" IsDefault="True"
              Background="##focus##" Foreground="White" BorderBrush="##focus##"/>
    </StackPanel>
    <Border Style="{StaticResource Card}" Padding="12,8,8,8">
      <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="CList" Margin="0,0,6,0"/></ScrollViewer>
    </Border>
  </DockPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse((Expand-Xaml $cx))
    if ($win.Icon) { $dlg.Icon = $win.Icon }
    $dlg.Add_SourceInitialized({ Set-DarkTitle ([System.Windows.Window]$this) })
    $wa = [System.Windows.SystemParameters]::WorkArea
    $dlg.Height = [math]::Min(640, $wa.Height - 40)

    $list = $dlg.FindName('CList'); $seg = $dlg.FindResource('Seg')
    $sum = Get-Summary @(Get-Days 14)
    $rows = @($sum.ByLabel.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 60)
    if (-not $rows) {
        $e = New-Object System.Windows.Controls.TextBlock; $e.Text = 'Nothing recorded yet.'; $e.Foreground = $Br.muted; [void]$list.Children.Add($e)
    }
    $i = 0
    foreach ($r in $rows) {
        $cur = $(if ($FocusCatMap.ContainsKey($r.Key)) { $FocusCatMap[$r.Key] } else { Get-FocusCategory $r.Key '' -Default })
        $g = New-Object System.Windows.Controls.Grid; $g.Margin = '0,4,0,4'; $g.Tag = $r.Key
        foreach ($w in '*', 'Auto', 'Auto') { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = $w; $g.ColumnDefinitions.Add($cd) }
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $r.Key; $t.Tag = 'raw'; $t.VerticalAlignment = 'Center'; $t.TextTrimming = 'CharacterEllipsis'; $t.FontWeight = 'Medium'
        $t.ToolTip = $r.Key
        $v = New-Object System.Windows.Controls.TextBlock; $v.Text = Format-Time $r.Value; $v.Foreground = $Br.ink2; $v.VerticalAlignment = 'Center'; $v.Margin = '12,0,12,0'
        [System.Windows.Controls.Grid]::SetColumn($v, 1)
        $b = New-Object System.Windows.Controls.Border; $b.Background = $Br.wash; $b.CornerRadius = 8; $b.Padding = 3
        [System.Windows.Controls.Grid]::SetColumn($b, 2)
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        foreach ($opt in @(@('work', 'Work'), @('neutral', 'Neutral'), @('distract', 'Distracting'))) {
            $rb = New-Object System.Windows.Controls.RadioButton
            $rb.Style = $seg; $rb.GroupName = "cat$i"; $rb.Content = $opt[1]; $rb.Tag = $opt[0]; $rb.FontSize = 12.5
            $rb.IsChecked = ($cur -eq $opt[0])
            [void]$sp.Children.Add($rb)
        }
        $b.Child = $sp
        [void]$g.Children.Add($t); [void]$g.Children.Add($v); [void]$g.Children.Add($b)
        [void]$list.Children.Add($g)
        $i++
    }

    $dlg.FindName('CSave').Add_Click({
        $d = [System.Windows.Window]::GetWindow($this)
        $map = @{}
        foreach ($k in $FocusCatMap.Keys) { $map[$k] = $FocusCatMap[$k] }
        foreach ($g in $d.FindName('CList').Children) {
            if (-not ($g -is [System.Windows.Controls.Grid])) { continue }
            $label = [string]$g.Tag
            $pick = @($g.Children[2].Child.Children | Where-Object { $_.IsChecked })[0].Tag
            if ((Get-FocusCategory $label '' -Default) -eq $pick) { $map.Remove($label) } else { $map[$label] = $pick }
        }
        Save-FocusCategories $map
        $script:FocusCatMap = Import-FocusCategories
        Reset-DataCache
        $d.DialogResult = $true
    })
    return $dlg
}

# ---------- Notification clicks: go to the right place ----------
function Invoke-Open([string]$what) {
    if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }
    [void]$win.Activate()
    switch ($what) {
        'review'    { $VRev.IsChecked = $true; if (-not (Test-FocusPlan (Get-FocusPlan (Get-FocusWeekId (Get-Date))))) { Show-Dialog (New-WeekPlanDialog) } }
        'plan'      { $VOver.IsChecked = $true; $R1.IsChecked = $true; Show-Dialog (New-DayPlanDialog $true) }
        'plantoday' { $VOver.IsChecked = $true; $R1.IsChecked = $true; Show-Dialog (New-DayPlanDialog $false) }
        'focus'     { $VOver.IsChecked = $true; $R1.IsChecked = $true; if ($FIdle.Visibility -eq 'Visible') { [void]$FTask.Focus() } }
        default     { $VOver.IsChecked = $true; $R1.IsChecked = $true }
    }
}

# ---------- Render ----------
$script:Days = 1; $script:View = 'overview'
$script:HourCats = @(); $script:TrendCats = @(); $script:ReviewCats = @()
$script:Settings = Get-FocusSettings

function Update-Status([bool]$on) {
    $script:On = $on
    $StatusDot.Fill = $(if ($on) { $Br.good } else { $Br.muted })
    $StatusText.Text = $(if ($on) { 'Tracking on' } else { 'Tracking off' })
    $ToggleBtn.Content = $(if ($on) { 'Stop tracking' } else { 'Start tracking' })
    if ($on) { $ToggleBtn.Background = $Br.surface; $ToggleBtn.Foreground = $Br.ink; $ToggleBtn.BorderBrush = $Br.border }
    else     { $ToggleBtn.Background = $Br.focus;   $ToggleBtn.Foreground = $Br.white; $ToggleBtn.BorderBrush = $Br.focus }
}

function Get-DayCats($perDay, [bool]$short) {
    foreach ($p in $perDay) {
        $dt = [datetime]::ParseExact($p.Date, 'yyyy-MM-dd', $null)
        [pscustomobject]@{ Label = $(if ($short) { [string]$dt.Day } else { $dt.ToString('ddd') })
                           Tip = $dt.ToString('dddd, d MMM'); F = $p.F; X = $p.X }
    }
}

function Render {
    $script:Settings = Get-FocusSettings
    $goal = 60 * [double]$script:Settings.GoalMinutes
    $limit = 60 * [double]$script:Settings.DailyLimitMinutes
    $v = $script:View
    $review = $v -eq 'review'
    $over = $v -eq 'overview'
    $vis = { param($on) if ($on) { 'Visible' } else { 'Collapsed' } }

    $Overview.Visibility    = & $vis $over
    $Tiles.Visibility       = & $vis $over
    $SessCard.Visibility    = & $vis $over
    $TrendCard.Visibility   = & $vis ($over -and $script:Days -gt 1)
    $ReviewPanel.Visibility = & $vis $review
    $DistPanel.Visibility   = & $vis ($v -eq 'distract')
    $SessPanel.Visibility   = & $vis ($v -eq 'sessions')
    $PatPanel.Visibility    = & $vis ($v -eq 'patterns')
    $RangeBox.Visibility    = & $vis (-not $review -and $v -ne 'patterns')
    $RangeNote.Text = $(if ($review) { 'Last 7 days vs the 7 before' } elseif ($v -eq 'patterns') { 'Last 4 to 12 weeks' } else { '' })

    Update-Status (Test-TrackerOn)
    $script:HasBlocker = Test-Blocker
    switch ($v) {
        'review'   { Render-Review $goal $limit; Render-WeekGoals }
        'distract' { Render-Distractions }
        'sessions' { Render-SessionsDash }
        'patterns' { Render-Patterns $goal }
        default    { Render-Overview $goal $limit }
    }
    Render-Sessions $(if ($over) { $script:Days } else { 7 })
    Render-Plan
    Render-FocusBar

    $alertsText = $(if ($script:Settings.AlertsOn) { 'Alerts on' } else { 'Alerts off' })
    $Foot.Text = 'Updated at ' + (Get-Date).ToString('HH:mm') + ' - refreshes every minute. ' + $alertsText + '. Your data stays on this computer.'
    Translate-Tree $win
}

function Render-Overview($goal, $limit) {
    $n = $script:Days
    $s = Get-Summary @(Get-Days $n)

    # Goal streak: consecutive days meeting the goal, ending today (or yesterday if today isn't done yet)
    $streak = 0
    if ($goal -gt 0) {
        $hist = @((Get-Summary @(Get-Days 60)).PerDay)
        $i = $hist.Count - 1
        if ($hist[$i].F -lt $goal) { $i-- }
        while ($i -ge 0 -and $hist[$i].F -ge $goal) { $streak++; $i-- }
    }
    $streakText = $(if ($streak -ge 2) { " - $streak-day streak" } elseif ($streak -eq 1) { ' - 1-day streak' } else { '' })

    # Tile 1: goal
    if ($goal -le 0) {
        $TGoalKey.Text = 'Daily goal'; $TGoal.Text = 'Not set'; Set-Meter $GoalA $GoalB 0; $TGoalSub.Text = 'Set one in Goals & alerts'
    } elseif ($n -eq 1) {
        $TGoalKey.Text = 'Daily goal'
        $TGoal.Text = Format-Time $s.Focus
        Set-Meter $GoalA $GoalB ($s.Focus / $goal)
        $TGoalSub.Text = $(if ($s.Focus -ge $goal) { 'Goal reached!' + $streakText } else { 'of ' + (Format-Hours $script:Settings.GoalMinutes) + ' goal' + $streakText })
    } else {
        $active = @($s.PerDay | Where-Object { $_.F + $_.X -gt 0 })
        $met = @($s.PerDay | Where-Object { $_.F -ge $goal }).Count
        $TGoalKey.Text = 'Days goal met'
        $TGoal.Text = "$met of $n"
        Set-Meter $GoalA $GoalB ($met / $n)
        $TGoalSub.Text = 'Goal: ' + (Format-Hours $script:Settings.GoalMinutes) + ' focused per day' + $streakText
    }

    # Tile 2: focused share
    $pct = $(if ($s.Total) { [int][math]::Round(100 * $s.Focus / $s.Total) } else { 0 })
    $TFocus.Text = $(if ($s.Total) { "$pct%" } else { '-' })
    $Meter.Visibility = $(if ($s.Total) { 'Visible' } else { 'Hidden' })
    $MeterF.Width = New-Object System.Windows.GridLength ([math]::Max(0.001, $pct)), 'Star'
    $MeterX.Width = New-Object System.Windows.GridLength (100 - $pct), 'Star'
    $TFocusSub.Text = $(if ($s.Total) { 'of ' + (Format-Time $s.Total) + ' active time' } else { 'No data yet' })

    # Tile 3: distracting vs daily limit
    $TLost.Text = Format-Time $s.Lost
    $activeDays = [math]::Max(1, @($s.PerDay | Where-Object { $_.F + $_.X -gt 0 }).Count)
    $perDay = $s.Lost / $(if ($n -gt 1) { $activeDays } else { 1 })
    if ($limit -gt 0) {
        Set-Meter $LimA $LimB ($perDay / $limit)
        if ($n -eq 1) { $TLostSub.Text = $(if ($s.Lost -ge $limit) { 'Over your ' + (Format-Time $limit) + ' daily limit' } else { 'of ' + (Format-Time $limit) + ' daily limit' }) }
        else { $TLostSub.Text = 'About ' + (Format-Time $perDay) + ' per day (limit ' + (Format-Time $limit) + ')' }
    } else { Set-Meter $LimA $LimB 0; $TLostSub.Text = 'No daily limit set' }

    # Tile 4: top distraction
    $sorted = @($s.ByLabel.GetEnumerator() | Sort-Object Value -Descending)
    $topBad = $sorted | Where-Object { $script:Bad.ContainsKey($_.Key) } | Select-Object -First 1
    $TTop.Text = $(if ($topBad) { $topBad.Key } else { 'None' })
    $TTopSub.Text = $(if ($topBad) { Format-Time $topBad.Value } else { 'Nice work' })

    # Top list: 10 rows, the rest folded into "Other"
    $TopList.Children.Clear()
    if (-not $sorted) {
        $e = New-Object System.Windows.Controls.TextBlock; $e.Text = 'No activity recorded for this period yet.'
        $e.Foreground = $Br.muted; $e.Margin = '0,20,0,20'; [void]$TopList.Children.Add($e)
    } else {
        $max = $sorted[0].Value
        foreach ($r in ($sorted | Select-Object -First 10)) {
            $brush = $(if ($script:Bad.ContainsKey($r.Key)) { $Br.distract } elseif ($script:Neu.ContainsKey($r.Key)) { $Br.other } else { $Br.focus })
            [void]$TopList.Children.Add((New-TopRow $r.Key $r.Value $max $s.Total $brush))
        }
        $rest = ($sorted | Select-Object -Skip 10 | Measure-Object Value -Sum).Sum
        if ($rest -gt 0) { [void]$TopList.Children.Add((New-TopRow 'Other apps & sites' $rest $max $s.Total $Br.other)) }
    }

    # Hour chart: only the span of hours with activity (at least 8 hours wide)
    $used = @(0..23 | Where-Object { $s.HourF[$_] + $s.HourX[$_] -gt 0 })
    $h0 = $(if ($used) { $used[0] } else { 8 }); $h1 = $(if ($used) { $used[-1] } else { 18 })
    while ($h1 - $h0 -lt 7) { if ($h0 -gt 0) { $h0-- }; if ($h1 - $h0 -lt 7 -and $h1 -lt 23) { $h1++ } }
    $script:HourCats = @(foreach ($h in $h0..$h1) {
        [pscustomobject]@{ Label = "${h}h"; Tip = ('{0:00}:00 - {1:00}:00' -f $h, (($h + 1) % 24)); F = $s.HourF[$h]; X = $s.HourX[$h] } })
    $HourSub.Text = $(if ($n -eq 1) { 'Active time by hour of the day' } else { "Active time by hour of the day, all $n days added up" })
    Draw-Stack $HourCanvas $script:HourCats $(if ($script:HourCats.Count -gt 14) { 2 } else { 1 })

    # Trend
    if ($n -gt 1) {
        $script:TrendCats = @(Get-DayCats $s.PerDay ($n -gt 7))
        Draw-Stack $TrendCanvas $script:TrendCats $(if ($n -gt 7) { 3 } else { 1 }) $goal
    }
}

function Render-Review($goal, $limit) {
    $this7 = Get-Summary @(Get-Days 7)
    $prev7 = Get-Summary @(Get-Days 7 7)
    $from = [datetime]::ParseExact($this7.PerDay[0].Date, 'yyyy-MM-dd', $null)
    $ReviewSub.Text = 'Last 7 days (' + $from.ToString('d MMM') + ' - ' + (Get-Date).ToString('d MMM') + ') compared with the 7 days before'

    $pctNow  = $(if ($this7.Total) { 100 * $this7.Focus / $this7.Total } else { 0 })
    $pctPrev = $(if ($prev7.Total) { 100 * $prev7.Focus / $prev7.Total } else { 0 })
    $metNow  = $(if ($goal -gt 0) { @($this7.PerDay | Where-Object { $_.F -ge $goal }).Count } else { 0 })
    $metPrev = $(if ($goal -gt 0) { @($prev7.PerDay | Where-Object { $_.F -ge $goal }).Count } else { 0 })

    $ReviewStats.Children.Clear()
    [void]$ReviewStats.Children.Add((New-Stat 'Focused time' (Format-Time $this7.Focus) (Get-Delta $this7.Focus $prev7.Focus)))
    [void]$ReviewStats.Children.Add((New-Stat 'Focus share' $(if ($this7.Total) { "$([int]$pctNow)%" } else { '-' }) $(if ($prev7.Total) { Get-Delta $pctNow $pctPrev -Percent } else { '' })))
    [void]$ReviewStats.Children.Add((New-Stat 'Distracting time' (Format-Time $this7.Lost) (Get-Delta $this7.Lost $prev7.Lost)))
    [void]$ReviewStats.Children.Add((New-Stat 'Days goal met' $(if ($goal -gt 0) { "$metNow of 7" } else { '-' }) $(if ($goal -gt 0) { "$metPrev of 7 the week before" } else { 'No goal set' })))

    # Highlights
    $Highlights.Children.Clear()
    $activeDays = @($this7.PerDay | Where-Object { $_.F + $_.X -gt 0 })
    if (-not $activeDays) {
        [void]$Highlights.Children.Add((New-Line 'No activity recorded in the last 7 days yet.' ''))
    } else {
        $best = $activeDays | Sort-Object F -Descending | Select-Object -First 1
        $worst = $activeDays | Sort-Object X -Descending | Select-Object -First 1
        $dayName = { param($d) ([datetime]::ParseExact($d, 'yyyy-MM-dd', $null)).ToString('dddd') }
        [void]$Highlights.Children.Add((New-Line (" $(& $dayName $best.Date), with $(Format-Time $best.F) focused.") 'Most focused day:'))
        if ($worst.X -gt 0) { [void]$Highlights.Children.Add((New-Line (" $(& $dayName $worst.Date), with $(Format-Time $worst.X) on distractions.") 'Most distracted day:')) }
        $peakX = 0..23 | Sort-Object { $this7.HourX[$_] } -Descending | Select-Object -First 1
        $peakF = 0..23 | Sort-Object { $this7.HourF[$_] } -Descending | Select-Object -First 1
        [void]$Highlights.Children.Add((New-Line (" around ${peakF}h.") 'Your most focused hour is'))
        if ($this7.HourX[$peakX] -gt 0) { [void]$Highlights.Children.Add((New-Line (" around ${peakX}h ($(Format-Time $this7.HourX[$peakX]) this week).") 'You get distracted most')) }
        $topBad = @($this7.ByLabel.GetEnumerator() | Where-Object { $script:Bad.ContainsKey($_.Key) } | Sort-Object Value -Descending | Select-Object -First 3)
        if ($topBad) {
            $list = ($topBad | ForEach-Object { "$($_.Key -replace '^\w+: ', '') ($(Format-Time $_.Value))" }) -join ', '
            [void]$Highlights.Children.Add((New-Line (" $list.") 'Top distractions:'))
        }
    }
    $ss = @(Get-FocusSessions 7)
    if ($ss) {
        $sDone = @($ss | Where-Object Done).Count
        $topTask = $ss | Where-Object Task | Group-Object Task | Sort-Object { ($_.Group | Measure-Object Secs -Sum).Sum } -Descending | Select-Object -First 1
        $txt = " $sDone completed, $(Format-Time (($ss | Measure-Object Secs -Sum).Sum)) in total" + $(if ($topTask) { ", most of it on '$($topTask.Name)'." } else { '.' })
        [void]$Highlights.Children.Add((New-Line $txt 'Focus sessions:'))
    }

    # Suggestions (simple rules)
    $Tips.Children.Clear()
    $tipList = New-Object System.Collections.Generic.List[object]
    if ($activeDays) {
        $distPct = $(if ($this7.Total) { 100 * $this7.Lost / $this7.Total } else { 0 })
        if ($distPct -ge 15 -and $topBad) {
            $tipList.Add(@('Cut the biggest distraction. ', ('Distractions took {0}% of your time, mostly {1}. Try keeping it closed during work hours, or log out so it takes effort to open.' -f [int]$distPct, ($topBad[0].Key -replace '^\w+: ', ''))))
        } elseif ($distPct -lt 5) {
            $tipList.Add(@('Great focus. ', 'Distractions were under 5% of your time this week. Keep doing what you are doing.'))
        }
        if ($this7.HourX[$peakX] -ge 600) {
            $tipList.Add(@("Plan around ${peakX}h. ", "That's when you drift most. Put a short break or easy tasks there, and keep hard work for ${peakF}h, your best hour."))
        }
        if ($goal -gt 0) {
            if ($metNow -eq 7) { $tipList.Add(@('Raise the bar? ', 'You met your goal every day. Consider a slightly higher daily goal.')) }
            elseif ($metNow -le 2 -and $activeDays.Count -ge 4) { $tipList.Add(@('Make the goal reachable. ', "You met it on $metNow of 7 days. A smaller goal you hit often builds the habit faster; you can raise it later.")) }
        }
        if ($prev7.Focus -gt 0) {
            $chg = 100 * ($this7.Focus - $prev7.Focus) / $prev7.Focus
            if ($chg -le -15) { $tipList.Add(@('Focused time dropped. ', ('About {0}% less than the week before. A busy week, or something pulling you away? Block focus time in your calendar.' -f [int][math]::Abs($chg)))) }
            elseif ($chg -ge 15) { $tipList.Add(@('Nice progress. ', ('Focused time is up {0}% from the week before.' -f [int]$chg))) }
        }
        if ($limit -gt 0) {
            $over = @($this7.PerDay | Where-Object { $_.X -ge $limit }).Count
            if ($over -ge 3) { $tipList.Add(@('Watch the daily limit. ', "You went over it on $over days. The alert is a good moment to close the tab and take a real break instead.")) }
        }
    }
    if ($activeDays -and -not $ss) {
        $tipList.Add(@('Try focus sessions. ', "Type one task above and press Start. For $($script:Settings.SessionMinutes) minutes you work only on that; distracting sites trigger an alert right away" + $(if ($script:HasBlocker) { ' and are blocked.' } else { '.' })))
    }
    if ($tipList.Count -eq 0) { $tipList.Add(@('Keep tracking. ', 'Suggestions get better with a full week of data.')) }
    for ($i = 0; $i -lt [math]::Min(4, $tipList.Count); $i++) { [void]$Tips.Children.Add((New-Line $tipList[$i][1] $tipList[$i][0])) }

    # Chart: last 7 days vs goal
    $ReviewChartSub.Text = $(if ($goal -gt 0) { 'Active time per day; the dashed line is your ' + (Format-Hours $script:Settings.GoalMinutes) + ' focus goal' } else { 'Active time per day' })
    $script:ReviewCats = @(Get-DayCats $this7.PerDay $false)
    Draw-Stack $ReviewCanvas $script:ReviewCats 1 $goal
}

# ---------- Settings dialog ----------
function New-SettingsDialog {
    $sx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Settings" Width="780" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="##page##" Foreground="##ink##" FontFamily="Segoe UI" FontSize="14" UseLayoutRounding="True">
  <Window.Resources>
##styles##
    <Style x:Key="Hint" TargetType="TextBlock" BasedOn="{StaticResource Sub}">
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="TextTrimming" Value="None"/><Setter Property="Margin" Value="0,2,0,6"/>
    </Style>
  </Window.Resources>
  <StackPanel Margin="22,18,22,20">
    <TextBlock Text="Settings" FontSize="18" FontWeight="SemiBold" Margin="0,0,0,14"/>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="32"/><ColumnDefinition/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="Goals and alerts" Style="{StaticResource H2}" Margin="0,0,0,10"/>
        <TextBlock Text="Daily focus goal (hours)" FontWeight="SemiBold"/>
        <TextBlock Text="Focused time you aim for each day. 0 turns the goal off." Style="{StaticResource Hint}"/>
        <TextBox x:Name="SGoal" Margin="0,0,0,12"/>

        <TextBlock Text="Daily distraction limit (minutes)" FontWeight="SemiBold"/>
        <TextBlock Text="One alert when you pass it. 0 turns it off." Style="{StaticResource Hint}"/>
        <TextBox x:Name="SLimit" Margin="0,0,0,12"/>

        <TextBlock Text="Alert after continuous distraction (minutes)" FontWeight="SemiBold"/>
        <TextBlock Text="When you stay on a distracting site this long. 0 turns it off." Style="{StaticResource Hint}"/>
        <TextBox x:Name="SStreak" Margin="0,0,0,12"/>

        <TextBlock Text="End-of-day summary at (HH:MM)" FontWeight="SemiBold"/>
        <TextBlock Text="Your day in one notification, plus a reminder to plan tomorrow. Empty turns it off." Style="{StaticResource Hint}"/>
        <TextBox x:Name="SSummary" Margin="0,0,0,12"/>

        <CheckBox x:Name="SAlerts" Content="Show notifications" Foreground="##ink##" Margin="0,2,0,0"/>
      </StackPanel>

      <StackPanel Grid.Column="2">
        <TextBlock Text="Focus sessions" Style="{StaticResource H2}" Margin="0,0,0,10"/>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="12"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <StackPanel><TextBlock Text="Session (minutes)" FontWeight="SemiBold"/><TextBox x:Name="SSession" Margin="0,6,0,0"/></StackPanel>
          <StackPanel Grid.Column="2"><TextBlock Text="Break (minutes)" FontWeight="SemiBold"/><TextBox x:Name="SBreak" Margin="0,6,0,0"/></StackPanel>
        </Grid>

        <TextBlock Text="Site blocking" Style="{StaticResource H2}" Margin="0,22,0,2"/>
        <TextBlock x:Name="SBlockStatus" Style="{StaticResource Hint}"/>
        <Button x:Name="SBlockSetup" Style="{StaticResource Btn}" Content="Set up site blocking" HorizontalAlignment="Left" Margin="0,4,0,10"/>
        <CheckBox x:Name="SBlockFocus" Content="Block distracting sites during focus sessions" Foreground="##ink##" Margin="0,4,0,8"/>
        <CheckBox x:Name="SBlockOn" Content="Also block them on a schedule" Foreground="##ink##" Margin="0,0,0,6"/>
        <StackPanel Orientation="Horizontal" Margin="22,2,0,0">
          <TextBlock Text="from" VerticalAlignment="Center" Foreground="##ink2##"/>
          <TextBox x:Name="SFrom" Width="70" Margin="8,0,8,0"/>
          <TextBlock Text="to" VerticalAlignment="Center" Foreground="##ink2##"/>
          <TextBox x:Name="STo" Width="70" Margin="8,0,0,0"/>
        </StackPanel>
        <CheckBox x:Name="SWeekdays" Content="Weekdays only" Foreground="##ink##" Margin="22,10,0,0"/>
      </StackPanel>
    </Grid>
    <TextBlock x:Name="SErr" Foreground="##ink##" FontWeight="SemiBold" Margin="0,10,0,0" TextWrapping="Wrap"/>
    <TextBlock x:Name="SVersion" Style="{StaticResource Sub}" Margin="0,10,0,-28" HorizontalAlignment="Left"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="SCancel" Style="{StaticResource Btn}" Content="Cancel" MinWidth="90" IsCancel="True"/>
      <Button x:Name="SSave" Style="{StaticResource Btn}" Content="Save" MinWidth="90" Margin="8,0,0,0" IsDefault="True"
              Background="##focus##" Foreground="White" BorderBrush="##focus##"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse((Expand-Xaml $sx))
    if ($win.Icon) { $dlg.Icon = $win.Icon }
    $dlg.Add_SourceInitialized({ Set-DarkTitle ([System.Windows.Window]$this) })
    $s = Get-FocusSettings
    $dlg.FindName('SGoal').Text = [string]([math]::Round($s.GoalMinutes / 60, 2))
    $dlg.FindName('SLimit').Text = [string]$s.DailyLimitMinutes
    $dlg.FindName('SStreak').Text = [string]$s.StreakAlertMinutes
    $dlg.FindName('SAlerts').IsChecked = [bool]$s.AlertsOn
    $dlg.FindName('SSummary').Text = [string]$s.SummaryTime
    $dlg.FindName('SSession').Text = [string]$s.SessionMinutes
    $dlg.FindName('SBreak').Text = [string]$s.BreakMinutes
    $dlg.FindName('SBlockFocus').IsChecked = [bool]$s.BlockDuringFocus
    $dlg.FindName('SBlockOn').IsChecked = [bool]$s.BlockOn
    $dlg.FindName('SFrom').Text = [string]$s.BlockFrom
    $dlg.FindName('STo').Text = [string]$s.BlockTo
    $dlg.FindName('SWeekdays').IsChecked = [bool]$s.BlockWeekdaysOnly
    $dlg.FindName('SVersion').Text = "Distraction Log $FocusVersion"
    Update-BlockStatus $dlg

    $dlg.FindName('SBlockSetup').Add_Click({
        $d = [System.Windows.Window]::GetWindow($this)
        $inst = Join-Path $FocusDir 'install-blocker.ps1'
        try {
            Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$inst`""
        } catch { $d.FindName('SErr').Text = Tr 'Setup was cancelled. Windows needs your OK (admin) to let the blocker edit the hosts file.' }
        Update-BlockStatus $d
    })

    $dlg.FindName('SSave').Add_Click({
        $dlg = [System.Windows.Window]::GetWindow($this)
        $err = $dlg.FindName('SErr')
        $num = {
            param($t)
            $v = 0.0
            if ([double]::TryParse($t.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -ge 0) { $v } else { $null }
        }
        $clock = '^([01]?\d|2[0-3]):[0-5]\d$'
        $g = & $num $dlg.FindName('SGoal').Text; $l = & $num $dlg.FindName('SLimit').Text; $k = & $num $dlg.FindName('SStreak').Text
        $sm = & $num $dlg.FindName('SSession').Text; $bm = & $num $dlg.FindName('SBreak').Text
        $sum = $dlg.FindName('SSummary').Text.Trim(); $from = $dlg.FindName('SFrom').Text.Trim(); $to = $dlg.FindName('STo').Text.Trim()
        if ($null -eq $g -or $g -gt 16) { $err.Text = Tr 'The goal should be a number of hours between 0 and 16.'; return }
        if ($null -eq $l -or $l -gt 600) { $err.Text = Tr 'The daily limit should be minutes between 0 and 600.'; return }
        if ($null -eq $k -or $k -gt 240) { $err.Text = Tr 'The continuous alert should be minutes between 0 and 240.'; return }
        if ($sum -and $sum -notmatch $clock) { $err.Text = Tr 'Write the summary time like 18:00, or leave it empty.'; return }
        if ($null -eq $sm -or $sm -lt 5 -or $sm -gt 180) { $err.Text = Tr 'A focus session should be between 5 and 180 minutes.'; return }
        if ($null -eq $bm -or $bm -gt 60) { $err.Text = Tr 'A break should be between 0 and 60 minutes.'; return }
        if ($from -notmatch $clock -or $to -notmatch $clock) { $err.Text = Tr 'Write the blocking hours like 09:00 and 12:00.'; return }
        $s = Get-FocusSettings
        $s.GoalMinutes = [int][math]::Round($g * 60); $s.DailyLimitMinutes = [int]$l; $s.StreakAlertMinutes = [int]$k
        $s.AlertsOn = [bool]$dlg.FindName('SAlerts').IsChecked; $s.SummaryTime = $sum
        $s.SessionMinutes = [int]$sm; $s.BreakMinutes = [int]$bm
        $s.BlockDuringFocus = [bool]$dlg.FindName('SBlockFocus').IsChecked; $s.BlockOn = [bool]$dlg.FindName('SBlockOn').IsChecked
        $s.BlockFrom = $from; $s.BlockTo = $to; $s.BlockWeekdaysOnly = [bool]$dlg.FindName('SWeekdays').IsChecked
        Save-FocusSettings $s
        $dlg.DialogResult = $true
    })
    return $dlg
}

function Update-BlockStatus($d) {
    $script:HasBlocker = Test-Blocker
    $st = $d.FindName('SBlockStatus'); $btn = $d.FindName('SBlockSetup')
    if ($script:HasBlocker) {
        $st.Text = Tr 'Set up. Blocks YouTube, Instagram, Facebook, TikTok, X, Netflix, Reddit, Twitch, Prime Video, Globoplay, Disney+, 9GAG and Pinterest. WhatsApp is not blocked.'
        $btn.Visibility = 'Collapsed'
    } else {
        $st.Text = Tr 'Needs a one-time setup. Windows will ask for your OK, because blocking edits the system hosts file.'
        $btn.Visibility = 'Visible'
    }
}

function Show-Settings { Show-Dialog (New-SettingsDialog) }

. (Join-Path $PSScriptRoot 'dashboards.ps1')
. (Join-Path $PSScriptRoot 'export.ps1')

# ---------- Events ----------
$R1.Add_Checked({ $script:Days = 1; Render })
$R7.Add_Checked({ $script:Days = 7; Render })
$R30.Add_Checked({ $script:Days = 30; Render })
$LEn.Add_Checked({ Set-AppLanguage 'en' })
$LPt.Add_Checked({ Set-AppLanguage 'pt' })
$VOver.Add_Checked({ $script:View = 'overview'; Render })
$VDist.Add_Checked({ $script:View = 'distract'; Render })
$VSess.Add_Checked({ $script:View = 'sessions'; Render })
$VPat.Add_Checked({ $script:View = 'patterns'; Render })
$VRev.Add_Checked({ $script:View = 'review'; Render })
foreach ($cv in @($DHourCanvas, $DTrendCanvas, $SChart, $PHeatF, $PHeatX, $PCal, $PSwitch)) {
    $cv.Add_SizeChanged({ if ($_.WidthChanged) { Redraw-Canvas $this } })
}
$SettingsBtn.Add_Click({ Show-Settings })
$CatBtn.Add_Click({ Show-Dialog (New-CatDialog) })
$ExportBtn.Add_Click({ Show-Dialog (New-ExportDialog) })
$PEdit.Add_Click({ Show-Dialog (New-DayPlanDialog $false) })
$PTomorrow.Add_Click({ Show-Dialog (New-DayPlanDialog $true) })
$WEdit.Add_Click({ Show-Dialog (New-WeekPlanDialog) })
$FStart.Add_Click({ Start-Focus })
$FTask.Add_KeyDown({ if ($_.Key -eq 'Return') { Start-Focus } })
$FTask.Add_TextChanged({ $FHint.Visibility = $(if ($FTask.Text) { 'Collapsed' } else { 'Visible' }) })
$FStop.Add_Click({ Stop-FocusSession; $script:LastState = 'idle'; Render })
$CoachBtn.Add_Click({
    $coach = Join-Path $FocusDir 'coach.ps1'
    $psArgs = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$coach`""
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    try {
        if ($wt) { Start-Process $wt.Source -ArgumentList "-w new --title `"Focus coach`" -d `"$FocusDir`" powershell.exe $psArgs" }
        else { Start-Process powershell.exe -ArgumentList $psArgs -WorkingDirectory $FocusDir }
    } catch { [System.Windows.MessageBox]::Show("Could not start the coach: $_", 'Distraction Log') | Out-Null }
})

# Last task name, ready for the next session
$FTask.Text = [string](Get-FocusSession).Task
if (Test-Path $openFile) { Remove-Item $openFile -Force -ErrorAction SilentlyContinue }
$HourCanvas.Add_SizeChanged({ if ($_.WidthChanged) { Draw-Stack $HourCanvas $script:HourCats $(if ($script:HourCats.Count -gt 14) { 2 } else { 1 }) } })
$TrendCanvas.Add_SizeChanged({ if ($_.WidthChanged -and $script:View -eq 'overview' -and $script:Days -gt 1) { Draw-Stack $TrendCanvas $script:TrendCats $(if ($script:Days -gt 7) { 3 } else { 1 }) (60 * [double]$script:Settings.GoalMinutes) } })
$ReviewCanvas.Add_SizeChanged({ if ($_.WidthChanged -and $script:View -eq 'review') { Draw-Stack $ReviewCanvas $script:ReviewCats 1 (60 * [double]$script:Settings.GoalMinutes) } })

$ToggleBtn.Add_Click({
    $ToggleBtn.IsEnabled = $false
    try {
        if (Test-TrackerOn) {
            Disable-ScheduledTask -TaskName 'Distraction Log' | Out-Null
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
                Where-Object { $_.CommandLine -like '*FocusLog\tracker.ps1*' } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
            Update-Status $false
        } else {
            Enable-ScheduledTask -TaskName 'Distraction Log' | Out-Null
            Start-ScheduledTask -TaskName 'Distraction Log'
            Update-Status $true
        }
    } catch {
        [System.Windows.MessageBox]::Show("Could not switch tracking: $_", 'Distraction Log') | Out-Null
    }
    # Re-check the real state a moment later
    $script:Check = New-Object System.Windows.Threading.DispatcherTimer
    $script:Check.Interval = [TimeSpan]::FromSeconds(3)
    $script:Check.Add_Tick({ $script:Check.Stop(); Update-Status (Test-TrackerOn); $ToggleBtn.IsEnabled = $true })
    $script:Check.Start()
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes(1)
$timer.Add_Tick({ Render })
$timer.Start()

# Every second: timer countdown, session changes, and requests from notification clicks
$script:LastState = (Get-FocusSession).State
$tick = New-Object System.Windows.Threading.DispatcherTimer
$tick.Interval = [TimeSpan]::FromSeconds(1)
$tick.Add_Tick({
    try {
        $s = Update-FocusSession
        if ($s.State -ne $script:LastState) { $script:LastState = $s.State; Render } else { Render-FocusBar $s }
        if ((Test-Path $openFile) -and $win.OwnedWindows.Count -eq 0) {
            $t = ([string](Get-Content $openFile -Raw)).Trim()
            Remove-Item $openFile -Force
            Invoke-Open $t
        }
    } catch {}
})
$tick.Start()

$win.Add_ContentRendered({ Render })
if ($Open -and -not $snap) { $win.Add_ContentRendered({ Invoke-Open $Open }) }

if ($snap) {
    $win.WindowState = 'Normal'; $win.Left = -6000; $win.Top = 0; $win.Width = 1100; $win.Height = 800; $win.ShowInTaskbar = $false
    $win.Add_ContentRendered({
        $grid = $win.Content.Content
        $grid.Background = $Br.page
        foreach ($tab in @(@($R1, 'today'), @($R7, 'week'), @($VDist, 'distractions'), @($VSess, 'sessions'), @($VPat, 'patterns'), @($VRev, 'review'))) {
            $tab[0].IsChecked = $true
            $win.UpdateLayout(); Render; $win.UpdateLayout()
            $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$grid.ActualWidth + 48), ([int]$grid.ActualHeight + 44), 96, 96, 'Pbgra32'
            $rtb.Render($grid)
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs = [IO.File]::Create((Join-Path $snap "$($tab[1]).png")); $enc.Save($fs); $fs.Close()
        }
        # Dialogs
        foreach ($pair in @(@((New-SettingsDialog), 'settings'), @((New-DayPlanDialog $true), 'plan'), @((New-WeekPlanDialog), 'weekplan'), @((New-CatDialog), 'categories'), @((New-ExportDialog), 'export'))) {
            $dlg = $pair[0]
            $dlg.WindowStartupLocation = 'Manual'; $dlg.Left = -6000; $dlg.Top = 0
            $dlg.Show(); Translate-Tree $dlg; $dlg.UpdateLayout()
            $root = $dlg.Content
            $bg = New-Object System.Windows.Controls.Border; $bg.Background = $Br.page
            $dlg.Content = $null; $bg.Child = $root; $dlg.Content = $bg; $dlg.UpdateLayout()
            $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$bg.ActualWidth), ([int]$bg.ActualHeight), 96, 96, 'Pbgra32'
            $rtb.Render($bg)
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs = [IO.File]::Create((Join-Path $snap "$($pair[1]).png")); $enc.Save($fs); $fs.Close()
            $dlg.Close()
        }
        # Optional: test switching the language live (FL_SNAPSWITCH = en or pt)
        if ($env:FL_SNAPSWITCH) {
            if ($env:FL_SNAPSWITCH -eq 'pt') { $LPt.IsChecked = $true } else { $LEn.IsChecked = $true }
            $VOver.IsChecked = $true; $R1.IsChecked = $true
            $win.UpdateLayout(); Render; $win.UpdateLayout()
            $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ([int]$grid.ActualWidth + 48), ([int]$grid.ActualHeight + 44), 96, 96, 'Pbgra32'
            $rtb.Render($grid)
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs = [IO.File]::Create((Join-Path $snap 'switched.png')); $enc.Save($fs); $fs.Close()
        }
        $win.Close()
    })
}
$ErrorActionPreference = 'Continue'   # a hiccup inside a click handler shouldn't close the app
[void]$win.ShowDialog()

} catch {
    ("{0}  {1}`r`n{2}" -f (Get-Date), $_, $_.ScriptStackTrace) | Out-File $errFile -Append -Encoding utf8
    try { [System.Windows.MessageBox]::Show("Distraction Log hit an error. Details: $errFile", 'Distraction Log') | Out-Null } catch {}
}

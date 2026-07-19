param(
    [string]$WhipKey = 'F7',
    [string]$PlaceKey = 'F9',
    [string]$NextKey = 'F10',
    [string]$AddMusicKey = 'F11',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$root = Split-Path $PSScriptRoot -Parent
$ipcDir = Join-Path $root 'ipc'
$commandFile = Join-Path $ipcDir 'menu_command.txt'
$showFile = Join-Path $ipcDir 'menu_show.txt'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force $ipcDir | Out-Null

$whipKeyFile = Join-Path $ipcDir 'whip_key.txt'
if (Test-Path -LiteralPath $whipKeyFile) {
    $reportedWhipKey = [IO.File]::ReadAllText($whipKeyFile, [Text.Encoding]::UTF8).Trim()
    if ($reportedWhipKey) { $WhipKey = $reportedWhipKey }
}

# Only one panel is needed. A second F6 press asks the existing panel to come
# back to the foreground instead of opening a duplicate window.
$mutex = New-Object System.Threading.Mutex($false, 'PalToolsControlPanel')
if (-not $mutex.WaitOne(0)) {
    [IO.File]::WriteAllText($showFile, [DateTime]::UtcNow.Ticks.ToString(), $utf8NoBom)
    exit 0
}

function Send-Command([string]$command) {
    # Put seq last: a reader that catches a partial write ignores it and tries
    # again on the next poll instead of executing an incomplete command.
    $lines = @(
        "command=$command"
        "seq=$([DateTime]::UtcNow.Ticks)"
    )
    [IO.File]::WriteAllText($commandFile, ($lines -join "`n"), $utf8NoBom)
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pal Tools" Width="420" Height="530"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Topmost="True" Background="#111827" Foreground="#F9FAFB"
        FontFamily="Segoe UI" ShowInTaskbar="True">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Margin" Value="0,6,0,0"/>
      <Setter Property="Padding" Value="14,10"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#2563EB"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
  </Window.Resources>
  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0">
      <TextBlock Text="PAL TOOLS" FontSize="26" FontWeight="Bold"/>
      <TextBlock Text="Whip and boombox controls in one place" Foreground="#9CA3AF" Margin="0,2,0,12"/>
    </StackPanel>

    <Border Grid.Row="1" Background="#1F2937" CornerRadius="8" Padding="14" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="Pal Whip" FontSize="18" FontWeight="Bold"/>
        <TextBlock x:Name="WhipHint" Foreground="#D1D5DB" Margin="0,3,0,2"/>
        <Button x:Name="WhipButton" Content="Crack Whip" Background="#DC2626"/>
      </StackPanel>
    </Border>

    <Border Grid.Row="2" Background="#1F2937" CornerRadius="8" Padding="14" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="Boombox" FontSize="18" FontWeight="Bold"/>
        <TextBlock x:Name="BoomboxHint" Foreground="#D1D5DB" Margin="0,3,0,2"/>
        <Button x:Name="ToggleButton" Content="Place / Pick Up Boombox"/>
        <UniformGrid Columns="2">
          <Button x:Name="NextButton" Content="Next Track" Margin="0,6,3,0" Background="#7C3AED"/>
          <Button x:Name="MusicButton" Content="Add Music" Margin="3,6,0,0" Background="#059669"/>
        </UniformGrid>
        <Grid Margin="0,6,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="48"/>
            <ColumnDefinition Width="48"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Listening volume" VerticalAlignment="Center" Foreground="#D1D5DB"/>
          <Button Grid.Column="1" x:Name="VolumeDownButton" Content="−" Margin="0,0,3,0" Padding="6,5" FontSize="17" Background="#475569"/>
          <Button Grid.Column="2" x:Name="VolumeUpButton" Content="+" Margin="3,0,0,0" Padding="6,5" FontSize="17" Background="#475569"/>
        </Grid>
      </StackPanel>
    </Border>

    <Border Grid.Row="3" Background="#0F172A" CornerRadius="6" Padding="10">
      <TextBlock x:Name="StatusText" Text="Choose an action. Results appear inside Palworld."
                 Foreground="#93C5FD" TextAlignment="Center"/>
    </Border>

    <TextBlock Grid.Row="4" VerticalAlignment="Bottom" TextAlignment="Center"
               Foreground="#6B7280" Margin="0,10,0,6"
               Text="The original hotkeys remain available as quick shortcuts."/>
    <Button Grid.Row="5" x:Name="CloseButton" Content="Close" Background="#374151"/>
  </Grid>
</Window>
'@

try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $whipButton = $window.FindName('WhipButton')
    $toggleButton = $window.FindName('ToggleButton')
    $nextButton = $window.FindName('NextButton')
    $musicButton = $window.FindName('MusicButton')
    $volumeDownButton = $window.FindName('VolumeDownButton')
    $volumeUpButton = $window.FindName('VolumeUpButton')
    $closeButton = $window.FindName('CloseButton')
    $statusText = $window.FindName('StatusText')
    $window.FindName('WhipHint').Text = "Equip the whip, then click below. Shortcut: $WhipKey"
    $window.FindName('BoomboxHint').Text = "Place it, change songs, or add your own music. Shortcuts: $PlaceKey / $NextKey / $AddMusicKey"

    if ($ValidateOnly) {
        Write-Output 'Pal Tools XAML: OK'
        exit 0
    }

    $whipButton.Add_Click({
        Send-Command 'whip'
        $statusText.Text = 'Whip command sent. Check Palworld for the result.'
    })
    $toggleButton.Add_Click({
        Send-Command 'boombox_toggle'
        $statusText.Text = 'Boombox command sent. Check Palworld for the result.'
    })
    $nextButton.Add_Click({
        Send-Command 'boombox_next'
        $statusText.Text = 'Track command sent. Check Palworld for the result.'
    })
    $musicButton.Add_Click({
        Send-Command 'music_add'
        $window.Close()
    })
    $volumeDownButton.Add_Click({
        Send-Command 'volume_down'
        $statusText.Text = 'Listening volume decreased by 10%.'
    })
    $volumeUpButton.Add_Click({
        Send-Command 'volume_up'
        $statusText.Text = 'Listening volume increased by 10%.'
    })
    $closeButton.Add_Click({ $window.Close() })

    $showTimer = New-Object Windows.Threading.DispatcherTimer
    $showTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $showTimer.Add_Tick({
        if (Test-Path -LiteralPath $showFile) {
            Remove-Item -LiteralPath $showFile -Force -ErrorAction SilentlyContinue
            $window.WindowState = [Windows.WindowState]::Normal
            $window.Show()
            $window.Activate()
            $window.Topmost = $false
            $window.Topmost = $true
        }
    })
    $showTimer.Start()
    [void]$window.ShowDialog()
    $showTimer.Stop()
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}

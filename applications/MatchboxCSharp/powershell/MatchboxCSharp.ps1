#requires -Version 7.0
using namespace System.Windows
using namespace System.Windows.Controls
using namespace System.Diagnostics

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Import-Module "$PSScriptRoot/../backend/Matchbox.Backend.psm1" -Force

$script:AppVersion = '0.1.0'
$script:IsDirty = $false
$script:Cancellation = $null

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Matchbox C# v0.1.0 | Joshua Dwight" Height="800" Width="1280" MinHeight="700" MinWidth="1100">
  <DockPanel LastChildFill="True">
    <Menu DockPanel.Dock="Top">
      <MenuItem Header="_File"><MenuItem x:Name="ExitMenu" Header="_Exit"/></MenuItem>
      <MenuItem Header="_Help"><MenuItem x:Name="ManualMenu" Header="_Manual"/><MenuItem x:Name="AboutMenu" Header="_About"/></MenuItem>
    </Menu>
    <StatusBar DockPanel.Dock="Bottom"><StatusBarItem><TextBlock x:Name="StatusText">Ready</TextBlock></StatusBarItem></StatusBar>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <GroupBox Header="Build Options" Grid.Row="0" Grid.Column="0" Margin="8">
        <Grid Margin="8">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <TextBlock Grid.Row="0" Grid.Column="0" Text="Configuration" Margin="0,0,8,8"/>
          <ComboBox x:Name="ConfigurationCombo" Grid.Row="0" Grid.Column="1" Margin="0,0,16,8"><ComboBoxItem>Debug</ComboBoxItem><ComboBoxItem>Release</ComboBoxItem></ComboBox>
          <TextBlock Grid.Row="0" Grid.Column="2" Text="Framework" Margin="0,0,8,8"/>
          <ComboBox x:Name="FrameworkCombo" Grid.Row="0" Grid.Column="3" Margin="0,0,0,8"><ComboBoxItem>net8.0</ComboBoxItem><ComboBoxItem>net9.0</ComboBoxItem></ComboBox>
          <TextBlock Grid.Row="1" Grid.Column="0" Text="Runtime" Margin="0,0,8,8"/>
          <ComboBox x:Name="RuntimeCombo" Grid.Row="1" Grid.Column="1" Margin="0,0,16,8"><ComboBoxItem>win-x64</ComboBoxItem><ComboBoxItem>win-arm64</ComboBoxItem></ComboBox>
          <TextBlock Grid.Row="1" Grid.Column="2" Text="Output Path" Margin="0,0,8,8"/>
          <TextBox x:Name="OutputPathText" Grid.Row="1" Grid.Column="3" Margin="0,0,0,8"/>
          <StackPanel Grid.Row="2" Grid.ColumnSpan="4" Orientation="Horizontal">
            <CheckBox x:Name="SingleFileCheck" Content="Single-file publish" Margin="0,0,16,0"/>
            <CheckBox x:Name="SelfContainedCheck" Content="Self-contained" Margin="0,0,16,0"/>
            <CheckBox x:Name="DebugModeCheck" Content="Debug mode"/>
          </StackPanel>
        </Grid>
      </GroupBox>
      <GroupBox Header="Execution Console" Grid.Row="0" Grid.RowSpan="2" Grid.Column="1" Margin="8">
        <Grid Margin="8"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
            <Button x:Name="BuildButton" Content="Build" Margin="0,0,8,0"/>
            <Button x:Name="RunButton" Content="Run" Margin="0,0,8,0"/>
            <Button x:Name="TestButton" Content="Test" Margin="0,0,8,0"/>
            <Button x:Name="CancelButton" Content="Cancel"/>
          </StackPanel>
          <TextBox x:Name="ConsoleText" Grid.Row="1" FontFamily="Consolas" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap"/>
        </Grid>
      </GroupBox>
      <GroupBox Header="Project + Arguments" Grid.Row="1" Grid.Column="0" Margin="8">
        <Grid Margin="8"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock Text="Project/Solution Path"/>
          <TextBox x:Name="ProjectPathText" Grid.Row="1" Margin="0,6,0,8"/>
          <TextBox x:Name="CustomArgumentsText" Grid.Row="2" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
        </Grid>
      </GroupBox>
    </Grid>
  </DockPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$names = 'ExitMenu','ManualMenu','AboutMenu','StatusText','ConfigurationCombo','FrameworkCombo','RuntimeCombo','OutputPathText','SingleFileCheck','SelfContainedCheck','DebugModeCheck','BuildButton','RunButton','TestButton','CancelButton','ConsoleText','ProjectPathText','CustomArgumentsText'
$ui = @{}
$names | ForEach-Object { $ui[$_] = $window.FindName($_) }
$ui.ConfigurationCombo.SelectedIndex = 0
$ui.FrameworkCombo.SelectedIndex = 0
$ui.RuntimeCombo.SelectedIndex = 0

function Get-SelectedText([ComboBox]$combo){ if($combo.SelectedItem){$combo.SelectedItem.Content}else{''}}

function Invoke-UiCommand([string]$command){
  if($script:Cancellation){ $script:Cancellation.Cancel() }
  $script:Cancellation = [Threading.CancellationTokenSource]::new()
  $ui.ConsoleText.Clear(); $ui.StatusText.Text = "Running dotnet $command..."
  $cfg = Get-SelectedText $ui.ConfigurationCombo
  $framework = Get-SelectedText $ui.FrameworkCombo
  $runtime = Get-SelectedText $ui.RuntimeCombo
  $argLine = New-MatchboxDotnetArguments -Configuration $cfg -Framework $framework -Runtime $runtime -Output $ui.OutputPathText.Text -SelfContained:$ui.SelfContainedCheck.IsChecked -SingleFile:$ui.SingleFileCheck.IsChecked -CustomArgs $ui.CustomArgumentsText.Text

  $psi = [ProcessStartInfo]::new('dotnet', "$command $argLine")
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $proc = [Process]::new(); $proc.StartInfo = $psi; $null = $proc.Start()

  $append = [Action[string]]{
    param($line)
    $window.Dispatcher.Invoke([Action]{ $ui.ConsoleText.AppendText("$line`r`n"); $ui.ConsoleText.ScrollToEnd() })
  }

  [Threading.Tasks.Task]::Run({
    param($p,$cb,$token)
    while(-not $p.StandardOutput.EndOfStream -and -not $token.IsCancellationRequested){ $cb.Invoke($p.StandardOutput.ReadLine()) }
    while(-not $p.StandardError.EndOfStream -and -not $token.IsCancellationRequested){ $cb.Invoke("[ERR] " + $p.StandardError.ReadLine()) }
    $p.WaitForExit()
  }, $script:Cancellation.Token).ContinueWith({ $window.Dispatcher.Invoke([Action]{ $ui.StatusText.Text = 'Ready' }) }) | Out-Null
}

$ui.BuildButton.Add_Click({ Invoke-UiCommand 'build' })
$ui.RunButton.Add_Click({ Invoke-UiCommand 'run' })
$ui.TestButton.Add_Click({ Invoke-UiCommand 'test' })
$ui.CancelButton.Add_Click({ if($script:Cancellation){ $script:Cancellation.Cancel(); $ui.StatusText.Text='Cancelled' } })
$ui.AboutMenu.Add_Click({ [MessageBox]::Show("Matchbox C#`nVersion: $script:AppVersion`nAuthor: Joshua Dwight`nhttps://github.com/joshdwight101/","About") })
$ui.ManualMenu.Add_Click({ [MessageBox]::Show("Open manual at: ..\\src\\MatchboxCSharp.App\\Resources\\Manual\\manual.html","Manual") })
$ui.ExitMenu.Add_Click({ $window.Close() })
$window.Add_Closing({ if($script:IsDirty){ if([MessageBox]::Show('Unsaved changes exist. Exit?','Exit','YesNo') -ne 'Yes'){ $_.Cancel = $true } } })

$window.ShowDialog() | Out-Null

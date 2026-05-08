using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text;
using System.Windows;
using System.Windows.Input;
using MatchboxCSharp.App.Services;

namespace MatchboxCSharp.App.ViewModels;

public sealed class MainWindowViewModel : INotifyPropertyChanged
{
    private readonly DotnetExecutionService _executionService = new();
    private readonly StringBuilder _consoleBuffer = new();
    private string _statusMessage = "Ready";

    public event PropertyChangedEventHandler? PropertyChanged;

    public string WindowTitle => "Matchbox C# v0.1.0 | Joshua Dwight";

    public ObservableCollection<string> Configurations { get; } = ["Debug", "Release"];
    public ObservableCollection<string> Frameworks { get; } = ["net8.0", "net9.0"];
    public ObservableCollection<string> Runtimes { get; } = ["win-x64", "win-arm64"];

    public string SelectedConfiguration { get; set; } = "Debug";
    public string SelectedFramework { get; set; } = "net8.0";
    public string SelectedRuntime { get; set; } = "win-x64";
    public string OutputPath { get; set; } = "";
    public bool PublishSingleFile { get; set; }
    public bool SelfContained { get; set; }
    public bool DebugMode { get; set; }
    public string ProjectPath { get; set; } = "";
    public string CustomArguments { get; set; } = "";

    public string StatusMessage { get => _statusMessage; set { _statusMessage = value; OnPropertyChanged(); } }
    public string ConsoleText => _consoleBuffer.ToString();

    public ICommand BuildCommand => new AsyncRelayCommand(() => ExecuteAsync("build"));
    public ICommand RunCommand => new AsyncRelayCommand(() => ExecuteAsync("run"));
    public ICommand TestCommand => new AsyncRelayCommand(() => ExecuteAsync("test"));
    public ICommand CancelCommand => new RelayCommand(() => _executionService.Cancel());
    public ICommand ExitCommand => new RelayCommand(() => Application.Current.Shutdown());
    public ICommand OpenManualCommand => new RelayCommand(() => MessageBox.Show("Manual window scaffold."));
    public ICommand OpenAboutCommand => new RelayCommand(() => MessageBox.Show("Matchbox C#\nAuthor: Joshua Dwight"));

    private async Task ExecuteAsync(string command)
    {
        StatusMessage = $"Running dotnet {command}...";
        _consoleBuffer.Clear();
        OnPropertyChanged(nameof(ConsoleText));

        await _executionService.ExecuteAsync(command, CustomArguments, line =>
        {
            Application.Current.Dispatcher.Invoke(() =>
            {
                _consoleBuffer.AppendLine(line);
                OnPropertyChanged(nameof(ConsoleText));
            });
        });

        StatusMessage = "Ready";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

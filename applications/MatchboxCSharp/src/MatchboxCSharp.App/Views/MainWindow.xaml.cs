using System.Windows;
using MatchboxCSharp.App.ViewModels;

namespace MatchboxCSharp.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainWindowViewModel();
    }
}

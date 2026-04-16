function Select-ObjectFromGrid {
    <#
    .SYNOPSIS
        Displays a WPF-based data grid for selecting objects from a collection.

    .DESCRIPTION
        The Select-ObjectFromGrid function presents a XAML-based WPF window containing
        a DataGrid that displays objects from an input collection. Users can select
        one or more items using checkboxes and confirm their selection with OK or
        cancel the operation with Cancel.

        This function is similar to Out-GridView but provides additional features
        such as column filtering, Select All/Deselect All buttons, and minimum/maximum
        selection validation.

    .PARAMETER InputObject
        The collection of PSCustomObject items to display in the grid.
        Accepts pipeline input.

    .PARAMETER Title
        The title to display in the window title bar.
        Defaults to "Select Items".

    .PARAMETER ColumnsToShow
        An optional array of property names to display as columns.
        If not specified, all properties from the first object are displayed.

    .PARAMETER MinSelection
        The minimum number of items that must be selected before OK can be clicked.
        Defaults to 0 (no minimum).

    .PARAMETER MaxSelection
        The maximum number of items that can be selected.
        Defaults to 0 (no maximum / unlimited).

    .EXAMPLE
        $selected = Get-Process | Select-Object Name, Id, CPU | Select-ObjectFromGrid

        Displays all processes in a grid and returns the selected items.

    .EXAMPLE
        $users = Get-ADUser -Filter * -Properties DisplayName, EmailAddress
        $selected = $users | Select-ObjectFromGrid -Title "Select Users" -ColumnsToShow DisplayName, EmailAddress

        Displays AD users with only DisplayName and EmailAddress columns.

    .EXAMPLE
        $items | Select-ObjectFromGrid -MinSelection 1 -MaxSelection 5

        Requires at least 1 selection and allows maximum 5 selections.

    .OUTPUTS
        PSCustomObject[]
        Returns an array of selected objects, or $null if cancelled.

    .NOTES
        Function  : Select-ObjectFromGrid
        Author    : John Billekens
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 2025.0129.1
        Requires  : Windows PowerShell 5.1 or PowerShell 7+ with Windows Desktop support
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [PSObject[]]$InputObject,

        [Parameter(Mandatory = $false)]
        [string]$Title = "Select Items",

        [Parameter(Mandatory = $false)]
        [string[]]$ColumnsToShow,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MinSelection = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxSelection = 0
    )

    begin {
        # Collect all pipeline input
        $allItems = [System.Collections.ArrayList]::new()
    }

    process {
        foreach ($item in $InputObject) {
            [void]$allItems.Add($item)
        }
    }

    end {
        if ($allItems.Count -eq 0) {
            Write-Warning "No items to display."
            return $null
        }

        # Load WPF assemblies
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase

        # Determine columns to display
        $firstItem = $allItems[0]
        if ($ColumnsToShow -and $ColumnsToShow.Count -gt 0) {
            $columns = $ColumnsToShow
        } else {
            $columns = $firstItem.PSObject.Properties.Name
        }

        # Build column definitions for XAML
        $columnXaml = ""
        foreach ($col in $columns) {
            $columnXaml += @"
                        <DataGridTextColumn Header="$col" Binding="{Binding $col}" IsReadOnly="True" Width="Auto">
                            <DataGridTextColumn.ElementStyle>
                                <Style TargetType="TextBlock">
                                    <Setter Property="VerticalAlignment" Value="Center"/>
                                    <Setter Property="Margin" Value="5,2"/>
                                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                                </Style>
                            </DataGridTextColumn.ElementStyle>
                        </DataGridTextColumn>
"@
        }

        # Create the XAML for the window
        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
       Width="1440"
       Height="900"
       WindowStartupLocation="CenterScreen"
       ResizeMode="CanResize"
       MinWidth="600"
       MinHeight="400">
    <Window.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#0F172A" Offset="0"/>
            <GradientStop Color="#1E293B" Offset="0.6"/>
            <GradientStop Color="#111827" Offset="1"/>
        </LinearGradientBrush>
    </Window.Background>

    <Window.Resources>
        <!-- Palette -->
        <Color x:Key="AccentColor">#3B82F6</Color>
        <Color x:Key="CardColor">#0B1221</Color>
        <SolidColorBrush x:Key="AccentBrush" Color="{StaticResource AccentColor}"/>
        <SolidColorBrush x:Key="AccentBrushLight" Color="#1F6FEB"/>
        <SolidColorBrush x:Key="CardBrush" Color="{StaticResource CardColor}"/>
        <SolidColorBrush x:Key="CardBorderBrush" Color="#24324D"/>
        <SolidColorBrush x:Key="TextBrush" Color="#F8FAFC"/>
        <SolidColorBrush x:Key="TextSubtleBrush" Color="#CBD5E1"/>
        <SolidColorBrush x:Key="BorderBrushLight" Color="#1F2937"/>

        <!-- Buttons -->
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="MinWidth" Value="110"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                               CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center"
                                             VerticalAlignment="Center"
                                             RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#2F6FE3"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#2257B8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#3B4B68"/>
                                <Setter Property="Foreground" Value="#6B7280"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary (ghost) button -->
        <Style x:Key="GhostButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#182033"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="#2D3B54"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                               BorderBrush="{TemplateBinding BorderBrush}"
                               BorderThickness="{TemplateBinding BorderThickness}"
                               CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center"
                                             VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#1F2940"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#151D31"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- DataGrid -->
        <Style TargetType="DataGrid">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="RowBackground" Value="#0F172A"/>
            <Setter Property="AlternatingRowBackground" Value="#111B2F"/>
            <Setter Property="Background" Value="#0B1221"/>
            <Setter Property="GridLinesVisibility" Value="None"/>
            <Setter Property="RowHeaderWidth" Value="0"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource BorderBrushLight}"/>
            <Setter Property="VerticalGridLinesBrush" Value="{StaticResource BorderBrushLight}"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Margin" Value="0"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
        </Style>

        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#142038"/>
            <Setter Property="Foreground" Value="{StaticResource TextSubtleBrush}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrushLight}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="Padding" Value="14,12"/>
        </Style>

        <Style TargetType="DataGridRow">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Margin" Value="0,0,0,2"/>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect Color="#20000000"
                                     BlurRadius="6"
                                     ShadowDepth="0"
                                     Opacity="0.12"/>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#1E3A8A"/>
                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                </Trigger>
                <MultiTrigger>
                    <MultiTrigger.Conditions>
                        <Condition Property="IsSelected" Value="True"/>
                        <Condition Property="IsKeyboardFocusWithin" Value="False"/>
                    </MultiTrigger.Conditions>
                    <Setter Property="Background" Value="#243451"/>
                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                </MultiTrigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="DataGridCell">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="14,12"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#1E3A8A"/>
                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                </Trigger>
                <MultiTrigger>
                    <MultiTrigger.Conditions>
                        <Condition Property="IsSelected" Value="True"/>
                        <Condition Property="IsKeyboardFocusWithin" Value="False"/>
                    </MultiTrigger.Conditions>
                    <Setter Property="Background" Value="#243451"/>
                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                </MultiTrigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="BorderBrush" Value="#9CA3AF"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Grid VerticalAlignment="Center" HorizontalAlignment="Center">
                            <Border x:Name="Border" Width="16" Height="16" CornerRadius="3" BorderThickness="1" BorderBrush="{TemplateBinding BorderBrush}" Background="{TemplateBinding Background}"/>
                            <Path x:Name="CheckMark" Data="M2,6 L6,10 L14,2" StrokeThickness="2" Stroke="#F8FAFC" StrokeEndLineCap="Round" StrokeStartLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#3B82F6"/>
                                <Setter TargetName="Border" Property="BorderBrush" Value="#3B82F6"/>
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#5B8EF6"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Border" Property="Opacity" Value="0.5"/>
                                <Setter TargetName="CheckMark" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,16">
            <TextBlock Text="Select items"
                      FontSize="24"
                      FontWeight="Bold"
                      Foreground="{StaticResource TextBrush}"/>
            <TextBlock Text="Beheer je selectie en bevestig je keuze."
                      FontSize="13"
                      Foreground="{StaticResource TextSubtleBrush}"
                      Margin="0,4,0,0"/>
        </StackPanel>

        <!-- Card -->
        <Border Grid.Row="1"
               Background="{StaticResource CardBrush}"
               CornerRadius="12"
               Padding="20"
               BorderBrush="{StaticResource CardBorderBrush}"
               BorderThickness="1">
            <Border.Effect>
                <DropShadowEffect Color="#33000000" BlurRadius="18" ShadowDepth="0" Opacity="0.28"/>
            </Border.Effect>

            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Selection actions -->
                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,12">
                    <Button Name="btnSelectAll" Content="Select All" Style="{StaticResource GhostButton}" Margin="0,0,10,0"/>
                    <Button Name="btnDeselectAll" Content="Deselect All" Style="{StaticResource GhostButton}"/>
                    <TextBlock Name="txtSelectionInfo"
                              VerticalAlignment="Center"
                              Margin="16,0,0,0"
                              FontSize="12"
                              Foreground="{StaticResource TextSubtleBrush}"/>
                </StackPanel>

                <!-- Data Grid -->
                <DataGrid Grid.Row="1"
                         Name="dataGrid"
                         AutoGenerateColumns="False"
                         CanUserAddRows="False"
                         CanUserDeleteRows="False"
                         SelectionMode="Single"
                         IsReadOnly="True"
                         AlternationCount="2"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto">
                    <DataGrid.Columns>
                        <DataGridTemplateColumn Header="" Width="50" CanUserResize="False">
                            <DataGridTemplateColumn.CellTemplate>
                                <DataTemplate>
                                    <CheckBox Name="chkSelect"
                                             IsChecked="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                                             HorizontalAlignment="Center"
                                             VerticalAlignment="Center"
                                             Margin="4,0"/>
                                </DataTemplate>
                            </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
$columnXaml
                    </DataGrid.Columns>
                </DataGrid>

                <!-- Status -->
                <TextBlock Grid.Row="2"
                           Name="txtStatus"
                           Margin="0,12,0,0"
                           FontSize="12"
                           Foreground="{StaticResource TextSubtleBrush}"/>
            </Grid>
        </Border>

        <!-- Footer buttons -->
        <StackPanel Grid.Row="2"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right"
                    Margin="0,18,0,0">
            <Button Name="btnCancel" Content="Cancel" Style="{StaticResource GhostButton}" IsCancel="True" Margin="0,0,10,0"/>
            <Button Name="btnOK" Content="OK" IsDefault="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

        # Create wrapper objects with IsSelected property and expose all original properties
        $wrappedItems = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        foreach ($item in $allItems) {
            $wrapper = [PSCustomObject]@{
                IsSelected = $false
            }
            # Add all original properties to the wrapper
            foreach ($col in $columns) {
                $wrapper | Add-Member -NotePropertyName $col -NotePropertyValue $item.$col -Force
            }
            # Store reference to original item
            $wrapper | Add-Member -NotePropertyName '_OriginalItem' -NotePropertyValue $item -Force
            $wrappedItems.Add($wrapper)
        }

        # Parse XAML
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
        $reader.Close()

        # Get controls
        $dataGrid = $window.FindName("dataGrid")
        $btnSelectAll = $window.FindName("btnSelectAll")
        $btnDeselectAll = $window.FindName("btnDeselectAll")
        $btnOK = $window.FindName("btnOK")
        $btnCancel = $window.FindName("btnCancel")
        $txtSelectionInfo = $window.FindName("txtSelectionInfo")
        $txtStatus = $window.FindName("txtStatus")

        # Use synchronized hashtable to share state with event handlers
        $state = [hashtable]::Synchronized(@{
            DialogResult     = $null
            SelectedItems    = @()
            WrappedItems     = $wrappedItems
            DataGrid         = $dataGrid
            Window           = $window
            MinSelection     = $MinSelection
            MaxSelection     = $MaxSelection
            TxtSelectionInfo = $txtSelectionInfo
            TxtStatus        = $txtStatus
            BtnOK            = $btnOK
        })

        # Function to update selection count and validate - stored in state for access in closures
        $state.UpdateSelection = {
            $selectedCount = @($state.WrappedItems | Where-Object { $_.IsSelected }).Count
            $totalCount = $state.WrappedItems.Count

            $infoText = "$selectedCount of $totalCount selected"
            if ($state.MinSelection -gt 0 -or $state.MaxSelection -gt 0) {
                $constraints = @()
                if ($state.MinSelection -gt 0) { $constraints += "min: $($state.MinSelection)" }
                if ($state.MaxSelection -gt 0) { $constraints += "max: $($state.MaxSelection)" }
                $infoText += " (" + ($constraints -join ", ") + ")"
            }
            $state.TxtSelectionInfo.Text = $infoText

            # Validate selection
            $valid = $true
            $statusText = ""

            if ($state.MinSelection -gt 0 -and $selectedCount -lt $state.MinSelection) {
                $valid = $false
                $statusText = "Please select at least $($state.MinSelection) item(s)."
            } elseif ($state.MaxSelection -gt 0 -and $selectedCount -gt $state.MaxSelection) {
                $valid = $false
                $statusText = "Please select no more than $($state.MaxSelection) item(s)."
            }

            $state.TxtStatus.Text = $statusText
            $state.TxtStatus.Foreground = if ($valid) { [System.Windows.Media.Brushes]::Gray } else { [System.Windows.Media.Brushes]::Red }
            $state.BtnOK.IsEnabled = $valid
        }.GetNewClosure()

        # Bind data
        $dataGrid.ItemsSource = $wrappedItems

        # Initial update
        & $state.UpdateSelection

        # Select All button
        $btnSelectAll.Add_Click({
            foreach ($item in $state.WrappedItems) {
                $item.IsSelected = $true
            }
            $state.DataGrid.Items.Refresh()
            & $state.UpdateSelection
        }.GetNewClosure())

        # Deselect All button
        $btnDeselectAll.Add_Click({
            foreach ($item in $state.WrappedItems) {
                $item.IsSelected = $false
            }
            $state.DataGrid.Items.Refresh()
            & $state.UpdateSelection
        }.GetNewClosure())

        # Handle checkbox changes - use PreviewMouseLeftButtonUp for better checkbox detection
        $dataGrid.Add_PreviewMouseLeftButtonUp({
            param($wpfSource, $wpfEvent)
            # Small delay to allow the binding to update
            $state.Window.Dispatcher.InvokeAsync($state.UpdateSelection, [System.Windows.Threading.DispatcherPriority]::Background)
        }.GetNewClosure())

        # Also handle keyboard space for checkbox toggle
        $dataGrid.Add_PreviewKeyUp({
            param($wpfSource, $wpfEvent)
            if ($wpfEvent.Key -eq [System.Windows.Input.Key]::Space) {
                $state.Window.Dispatcher.InvokeAsync($state.UpdateSelection, [System.Windows.Threading.DispatcherPriority]::Background)
            }
        }.GetNewClosure())

        # OK button
        $btnOK.Add_Click({
            $state.DialogResult = $true
            $state.SelectedItems = @($state.WrappedItems | Where-Object { $_.IsSelected } | ForEach-Object { $_._OriginalItem })
            $state.Window.Close()
        }.GetNewClosure())

        # Cancel button
        $btnCancel.Add_Click({
            $state.DialogResult = $false
            $state.Window.Close()
        }.GetNewClosure())

        # Show dialog
        [void]$window.ShowDialog()

        # Return results
        if ($state.DialogResult -eq $true) {
            return $state.SelectedItems
        } else {
            return $null
        }
    }
}

# SIG # Begin signature block
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAv8tOBd8L6IRVL
# enT+iTyeHTfsEsvxwfx6l8GtjyejbKCCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbCMIIEqqADAgECAhMzAABWh4wS
# B8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcNMjYwNDE3
# MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCUBmrWP3Xv
# 3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJRMFvsnkv
# snlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZepiMgApJH
# y/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvTvEvEaBih
# OXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx41hHZDwe
# dcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFBdzkOeKdF
# lPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7XBQ96IxVj
# TBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLIpe0A/k8F
# zkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB0TAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0GA1UdDgQW
# BBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyHFjdGoKze
# efn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBF
# T0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# SUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYDVR0gBE0w
# SzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEA
# PH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK16b9Z6Cd
# Y/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqop5hxzlEM
# xv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3jx2jHKIUE
# RVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc7Kuy0Xw7
# eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/2mvAfQ6v
# cSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859WMNT/JjUU
# UJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaPEtvCkBQ2
# c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPlc6c8KaIC
# RjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW3NKtraSj
# z5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJc3OGnVii
# Xx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggbCMIIEqqADAgECAhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jv
# c29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcN
# MjYwNDE3MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJy
# YWJhbnQxEjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtl
# bnMgQ29uc3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRh
# bmN5MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCU
# BmrWP3Xv3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJ
# RMFvsnkvsnlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZe
# piMgApJHy/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvT
# vEvEaBihOXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx
# 41hHZDwedcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFB
# dzkOeKdFlPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7X
# BQ96IxVjTBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLI
# pe0A/k8FzkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB
# 0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEE
# AYI3YQEABggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0G
# A1UdDgQWBBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyH
# FjdGoKzeefn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIw
# Q1MlMjBFT0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUH
# MAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9z
# b2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYD
# VR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwF
# AAOCAgEAPH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK
# 16b9Z6CdY/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqo
# p5hxzlEMxv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3j
# x2jHKIUERVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc
# 7Kuy0Xw7eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/
# 2mvAfQ6vcSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859W
# MNT/JjUUUJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaP
# EtvCkBQ2c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPl
# c6c8KaICRjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW
# 3NKtraSjz5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJ
# c3OGnViiXx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggcoMIIFEKAD
# AgECAhMzAAAAFydFCQuLh6/GAAAAAAAXMA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNV
# BAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMT
# K01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIwMjEwHhcN
# MjYwMzI2MTgxMTMxWhcNMzEwMzI2MTgxMTMxWjBaMQswCQYDVQQGEwJVUzEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQg
# SUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEAgsdk/gMPZioBlcyfk6tDzJ+PRt4rSLGKW8ewpS0kRxXtURC3T3Gd
# bCKljobEn8ussqhGqQpRh/SXvRVwNXEIGb76UG5IPkCJ1S6/9BD61QQsKzPepW0S
# Nj8TXgsFxvS7MltoRuikIIp7Q5jQgaOM6QyK9++6ZVXUpYmZulAe6x8JrwZ0dNkE
# +rZ66lqtoocwepUSVUxM7odDmn8yDHjJ2DNPsfr3uRDix3X4qvh14jH/SW+2Cx7W
# IMhyIiQO201i6hUixmk4e2ZW8W7C1wPdTjq6BKb+zo8xbrt7ZKQvRX5QOA6dhLqu
# Pqj5sVKnxqfk19IC0SafTSTs8yC43Ew965BRRW8VL9ccoOmr4rxQy7aCgYTNk3dd
# /LphNaTTmnGp7kmLTxyHkB5geoWhYuuGrywS8E0wJv0W4rfOtHBV0e9sKvuUIeIU
# pnsx6ilxEVj6VQXvgD6yeCKnPmj3jJiJKAlmUDtth5yzRVBUl44sMiG4L5R/yyAC
# RKk2n088Q2YCoZS1O86+oMLKt1jaXGECOjbsVp8Id1VQw8he6J0KirOS5e25XlTd
# GPFb6oBOOaacgW78Kjf0bp+XzAgkc92mDGNJGYSjvdnj+7eMx6meW0DAIGdLRNj8
# /429MIspFBfz3KDqqpN71S4kQ2LLer3dxhDDczKVFL0HLwRuOvgjiG8CAwEAAaOC
# AdwwggHYMA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4E
# FgQUmvFUd3UMhxY3RqCs3nn59H/BeOkwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYI
# KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9S
# ZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMB
# Af8ECDAGAQH/AgEAMB8GA1UdIwQYMBaAFNlBKbAPD2Ns72nX9c0pnqRIajDmMHAG
# A1UdHwRpMGcwZaBjoGGGX2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUy
# MFBDQSUyMDIwMjEuY3JsMH0GCCsGAQUFBwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJ
# RCUyMFZlcmlmaWVkJTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDIxLmNydDAN
# BgkqhkiG9w0BAQwFAAOCAgEAkHVaGf1NJt/JdoimmRZbMWr6baaDi8mkdWvWStk0
# hdZDpxSYTA7HuipAoLL3qIhI101XOl7fOiCh5++jZOamQdAV79ojEUNoIgCZmL2X
# JrLaGanwdjNynecJyYVCTrRf2+h7KknpWOp4axdOs6K9ZQ5g0IsQWXCwfc0dfkSk
# LKNY3pDcWLlJPh2jd5NUue6pNDv/2G5MFNJhCwltODebyAjGceU+XOzav+7i721Y
# QnQ+39m2aQOFO7zpAdaKAeAGhEd6Y6CdDGneSxcoujWvafWbv4ay3jo1ORSLUuWM
# bKr5X18QE4Sde+gppGLLSkZsrUh2eyYSkX1envWX7ZPzg2/wiuKRlQFarDn+N9+2
# 0BqzhxwkNyLzfYJp1Lg4fCXb24XqFjx8SDdRgebFImOfOLVze8XQ/CwkrEaib0PH
# u2t4GVk4FYroEbNUFqvjdBvTY3uiR5TdQoyXoYHvh+TxpLSY2vo7hhK9D/rpEpHC
# +qmmcRUE4d0gyO9Zb1vvt25fxM3ekjvDfVHcPq3qMr0Rwsk4krKZWUEgU1SXT5qN
# 6gqRrshxbT6OQgZ9/xT04qiXdzPQR6KindBvSpoOnxnALxcJyzVwNpKL+9u8EZYy
# 98qX6i+4gE/2J6cbpekcB0ZXDn/XQxoNUUb6/djT/wllVyG+vIHkdq71PzbH5rYx
# dcAwggeeMIIFhqADAgECAhMzAAAAB4ejNKN7pY4cAAAAAAAHMA0GCSqGSIb3DQEB
# DAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAyMDAeFw0yMTA0MDEyMDA1MjBaFw0z
# NjA0MDEyMDE1MjBaMGMxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xNDAyBgNVBAMTK01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2Rl
# IFNpZ25pbmcgUENBIDIwMjEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCy8MCvGYgo4t1UekxJbGkIVQm0Uv96SvjB6yUo92cXdylN65Xy96q2YpWCiTas
# 7QPTkGnK9QMKDXB2ygS27EAIQZyAd+M8X+dmw6SDtzSZXyGkxP8a8Hi6EO9Zcwh5
# A+wOALNQbNO+iLvpgOnEM7GGB/wm5dYnMEOguua1OFfTUITVMIK8faxkP/4fPdEP
# CXYyy8NJ1fmskNhW5HduNqPZB/NkWbB9xxMqowAeWvPgHtpzyD3PLGVOmRO4ka0W
# csEZqyg6efk3JiV/TEX39uNVGjgbODZhzspHvKFNU2K5MYfmHh4H1qObU4JKEjKG
# sqqA6RziybPqhvE74fEp4n1tiY9/ootdU0vPxRp4BGjQFq28nzawuvaCqUUF2PWx
# h+o5/TRCb/cHhcYU8Mr8fTiS15kRmwFFzdVPZ3+JV3s5MulIf3II5FXeghlAH9Cv
# icPhhP+VaSFW3Da/azROdEm5sv+EUwhBrzqtxoYyE2wmuHKws00x4GGIx7NTWznO
# m6x/niqVi7a/mxnnMvQq8EMse0vwX2CfqM7Le/smbRtsEeOtbnJBbtLfoAsC3TdA
# OnBbUkbUfG78VRclsE7YDDBUbgWt75lDk53yi7C3n0WkHFU4EZ83i83abd9nHWCq
# fnYa9qIHPqjOiuAgSOf4+FRcguEBXlD9mAInS7b6V0UaNwIDAQABo4ICNTCCAjEw
# DgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTZQSmw
# Dw9jbO9p1/XNKZ6kSGow5jBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUyH7SaoUqG8oZmAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsw
# eaB3oHWGc2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jv
# c29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmlj
# YXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcmwwgcMGCCsGAQUFBwEBBIG2MIGzMIGB
# BggrBgEFBQcwAoZ1aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0
# cy9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBD
# ZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3J0MC0GCCsGAQUFBzABhiFo
# dHRwOi8vb25lb2NzcC5taWNyb3NvZnQuY29tL29jc3AwDQYJKoZIhvcNAQEMBQAD
# ggIBAH8lKp7+1Kvq3WYK21cjTLpebJDjW4ZbOX3HD5ZiG84vjsFXT0OB+eb+1TiJ
# 55ns0BHluC6itMI2vnwc5wDW1ywdCq3TAmx0KWy7xulAP179qX6VSBNQkRXzReFy
# jvF2BGt6FvKFR/imR4CEESMAG8hSkPYso+GjlngM8JPn/ROUrTaeU/BRu/1RFESF
# VgK2wMz7fU4VTd8NXwGZBe/mFPZG6tWwkdmA/jLbp0kNUX7elxu2+HtHo0QO5gdi
# KF+YTYd1BGrmNG8sTURvn09jAhIUJfYNotn7OlThtfQjXqe0qrimgY4Vpoq2MgDW
# 9ESUi1o4pzC1zTgIGtdJ/IvY6nqa80jFOTg5qzAiRNdsUvzVkoYP7bi4wLCj+ks2
# GftUct+fGUxXMdBUv5sdr0qFPLPB0b8vq516slCfRwaktAxK1S40MCvFbbAXXpAZ
# nU20FaAoDwqq/jwzwd8Wo2J83r7O3onQbDO9TyDStgaBNlHzMMQgl95nHBYMelLE
# HkUnVVVTUsgC0Huj09duNfMaJ9ogxhPNThgq3i8w3DAGZ61AMeF0C1M+mU5eucj1
# Ijod5O2MMPeJQ3/vKBtqGZg4eTtUHt/BPjN74SsJsyHqAdXVS5c+ItyKWg3Eforh
# ox9k3WgtWTpgV4gkSiS4+A09roSdOI4vrRw+p+fL4WrxSK5nMYIXMjCCFy4CAQEw
# cTBaMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0AhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCWCGSAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIB
# DDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IOTZIGsBZSr3ySpRJ7O8oYm5pFn22G25QrLw0j4+i13ZMA0GCSqGSIb3DQEBAQUA
# BIIBgLLwej89YuKxd4/IBpGju1Iu1Ju66C0uL8NWTKShpGzsKCYwKWKG+EHCctqW
# qDe8m3UWbU5g6cxvHf24sGN16BxLxEnf+NuljYCWYU380jkDM7Za+MlAJ3sJOtCl
# 7dukEjUkXctiwOE78EcTA2ALldT3d0j6mr+ZLlSpqE4kIj0yeqUiZJDtmSQwxuhH
# NBpX3dXRU4Fuhxub/h71/kYPyKXQgCURlYmQUS/3e9zUXrEfsZO3qeyJZF0zEKDq
# j4Yqt/9rRWY+tAVGHcetdS1aucoS/HhstQQ5BPzcvEmS+O4B6ukRLFIcMPHnIc2l
# LmBAR5pWHspHzkK3XSdQPSZ8cLEJfyvhghZDHH72RRShevnKsAWPX0GLr3oshpwv
# h83PIuXprxS/7Gosncau2G4ulA2dRyUGyiYLU3uyfTkIf5edlWobWBr6y5IQ2bM/
# 5UzZAFROpjXAXNRd7PcthF6p0EyIwtUcmULrZ3kyRjS5qsMU+H2SR+3KahQd/bF0
# Weh3RqGCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCiFVt/q9ZTp63w
# 4zqXE0a7JkOtOEqG8wPBmpzmw4ivaQIGacZcchqDGBMyMDI2MDQxNTE5NDQyMy4y
# NjVaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0NTFBLTA1RTAtRDk0NzE1
# MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRo
# b3JpdHmggg8pMIIHgjCCBWqgAwIBAgITMwAAAAXlzw//Zi7JhwAAAAAABTANBgkq
# hkiG9w0BAQwFADB3MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMUgwRgYDVQQDEz9NaWNyb3NvZnQgSWRlbnRpdHkgVmVyaWZpY2F0
# aW9uIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMjAwHhcNMjAxMTE5MjAz
# MjMxWhcNMzUxMTE5MjA0MjMxWjBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJT
# QSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAJ5851Jj/eDFnwV9Y7UGIqMcHtfnlzPREwW9ZUZHd5HBXXBvf7KrQ5cM
# SqFSHGqg2/qJhYqOQxwuEQXG8kB41wsDJP5d0zmLYKAY8Zxv3lYkuLDsfMuIEqvG
# YOPURAH+Ybl4SJEESnt0MbPEoKdNihwM5xGv0rGofJ1qOYSTNcc55EbBT7uq3wx3
# mXhtVmtcCEr5ZKTkKKE1CxZvNPWdGWJUPC6e4uRfWHIhZcgCsJ+sozf5EeH5KrlF
# nxpjKKTavwfFP6XaGZGWUG8TZaiTogRoAlqcevbiqioUz1Yt4FRK53P6ovnUfANj
# IgM9JDdJ4e0qiDRm5sOTiEQtBLGd9Vhd1MadxoGcHrRCsS5rO9yhv2fjJHrmlQ0E
# IXmp4DhDBieKUGR+eZ4CNE3ctW4uvSDQVeSp9h1SaPV8UWEfyTxgGjOsRpeexIve
# R1MPTVf7gt8hY64XNPO6iyUGsEgt8c2PxF87E+CO7A28TpjNq5eLiiunhKbq0Xbj
# kNoU5JhtYUrlmAbpxRjb9tSreDdtACpm3rkpxp7AQndnI0Shu/fk1/rE3oWsDqMX
# 3jjv40e8KN5YsJBnczyWB4JyeeFMW3JBfdeAKhzohFe8U5w9WuvcP1E8cIxLoKSD
# zCCBOu0hWdjzKNu8Y5SwB1lt5dQhABYyzR3dxEO/T1K/BVF3rV69AgMBAAGjggIb
# MIICFzAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYE
# FGtpKDo1L0hjQM972K9J6T7ZPdshMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsG
# AQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVw
# b3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAwe
# CgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTIftJqhSob
# yhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHegdYZzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBWZXJp
# ZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAyMDIw
# LmNybDCBlAYIKwYBBQUHAQEEgYcwgYQwgYEGCCsGAQUFBzAChnVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElkZW50aXR5
# JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5
# JTIwMjAyMC5jcnQwDQYJKoZIhvcNAQEMBQADggIBAF+Idsd+bbVaFXXnTHho+k7h
# 2ESZJRWluLE0Oa/pO+4ge/XEizXvhs0Y7+KVYyb4nHlugBesnFqBGEdC2IWmtKMy
# S1OWIviwpnK3aL5JedwzbeBF7POyg6IGG/XhhJ3UqWeWTO+Czb1c2NP5zyEh89F7
# 2u9UIw+IfvM9lzDmc2O2END7MPnrcjWdQnrLn1Ntday7JSyrDvBdmgbNnCKNZPmh
# zoa8PccOiQljjTW6GePe5sGFuRHzdFt8y+bN2neF7Zu8hTO1I64XNGqst8S+w+RU
# die8fXC1jKu3m9KGIqF4aldrYBamyh3g4nJPj/LR2CBaLyD+2BuGZCVmoNR/dSpR
# Cxlot0i79dKOChmoONqbMI8m04uLaEHAv4qwKHQ1vBzbV/nG89LDKbRSSvijmwJw
# xRxLLpMQ/u4xXxFfR4f/gksSkbJp7oqLwliDm/h+w0aJ/U5ccnYhYb7vPKNMN+SZ
# DWycU5ODIRfyoGl59BsXR/HpRGtiJquOYGmvA/pk5vC1lcnbeMrcWD/26ozePQ/T
# WfNXKBOmkFpvPE8CH+EeGGWzqTCjdAsno2jzTeNSxlx3glDGJgcdz5D/AAxw9Sdg
# q/+rY7jjgs7X6fqPTXPmaCAJKVHAP19oEjJIBwD1LyHbaEgBxFCogYSOiUIr0Xqc
# r1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIBAgITMwAAAFxhTACmp/LpIwAAAAAA
# XDANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBU
# aW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAxMDgxODU5MDZaFw0yNzAxMDcxODU5
# MDZaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0NTFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCuNYzOVXmTR3eDbVZVMTaDh6n+nv04
# Jw4zW6v7OTN1oTSxBIhyq6QKMBanA2eXpOyqQ0VvcXgcC5Sz3aMgldXyKR79bMIe
# LVPQtXSCsjrrLjd9mpdd5VQq4HfKgaisPLFv6ynp1x2g1veINh5V+bLEFp1XCqWW
# CEd1KRMQpkUkLSFRBZaFmb6Nz3MGrRAmU4nxt0wIV/20wSlzhaFKalpP0hSwI+1s
# VCxN8H8rlgh+0jGNZgCJEnXKw3SO/wJEjRhZMPaUSGEX7cwCrzqj/y1hnA+a8Gbw
# fZ0lCQPmMrjbcvx3j1VL6VecFnpdhfyP5ApLH5CSkXtNYhiFi7mG889+Miz+Ccr7
# awPiFP1LvAR9CTDZHz4ua/A5r4jOehH9AU7eEPxulAwy0BBywOl7tpK3gKMexwQy
# gHFpZe5d7TPiuVzKwktbh9ro4CkDwcpdUHCRgysNOuZr8Wd60f9DLkiooQFRh/mi
# cZx82DUTDlM5Ctcl4Ns4HejZNRGr+Gvd7V9kKuZF6XmW2td9qIZGL4eb515I0FUP
# RycH3viftPZVKYDbkh8G/4I84tmfPh4PacHu6JCdkC0BsOU0EZMP8Su2h9NmgwVz
# k86NVH7f1JhFcWwsxZxhRgI3K9EcH5xhWiMsqxebmZkrFighdqO7+yzozZZ3lkkq
# BWikYTg7ikY8PwIDAQABo4IByzCCAccwHQYDVR0OBBYEFK77MhyRGGREOW504FoD
# Eie6JOdpMB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwGA1UdHwRl
# MGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJT
# QSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYDVR0gBF8w
# XTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeBDAEEAjAN
# BgkqhkiG9w0BAQwFAAOCAgEAhXbQN9yxJIQFnYCFueVeZ09WRv1WkODNsgQQ7iCl
# H9tHz1tD6pbi0LT3KHa1xmQ3gojjdzqd5FE1wGMAaZvu2DzKyW0ZWYDED7BbW0nR
# wvWxE9DSVfKFwxhFgTkHu5cMB9Ofj2te8Qdv5plXp1lra2V9dSPAaBY3D9g8GUie
# V9Ruk03uhmCZffR+fIobO07/0xGT+3PJo+nlXjgrIsihl6UU2CS/cpbbenCinHJn
# K2lUozE7+N25qSyy9Vgqvsv09xxLY14syl0aOZt0xOvVIIqLKmeui3h9HbxQfbtf
# gexLQ40z7wsnOJ/N/lt75vQaswZr39xEoMLeCeShyvgqMionmkQXT961Ti6LpNzG
# hZABR7YVpX+q84f9A6Kbl8amG8txKLdXOd9DKkCd9b+9sSTEnuULPsyuearCoNtr
# 3JOm9psIQ/2TYeumHgbFWNpEvWoZBjLUfjoD89A5w4vjnketG8ImRyYn8MhzE3Br
# k/aVJ6e5wrentLyIYbZidbZRCDLq1uEmLVColC8z+ki3avMrNfgVKIQobf7YIvom
# 1n00p6O73gQu8WiYuibJKgPxPD3RM1Dlh2m8GIkh15WTG6Gzk0dA5NyM2qoFFF/h
# NsbH5lY9qLrYb1meeXNfz3yytaeMs0Xvfq2N1eDYtDkRlEFoXn4JDWLKQdY2Ylw6
# vIMxggPUMIID0AIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAXGFMAKan8ukjAAAAAABcMA0GCWCGSAFl
# AwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIEJ8sHkLLVTqM3941bsuwoShtwfz3K33SboUKE+3qySJMIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQg97pqQYd3bjD5LeiLZCbTs0cAUbdUPCOdd6vJ
# a36g7twwfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABcYUwApqfy6SMAAAAAAFwwIgQgrcci9b7HOIxK
# IBH7Yg3Er3Da6Q80fPLQHn+iyLjKhfQwDQYJKoZIhvcNAQELBQAEggIAOP7mKHGj
# fOmG4qmbhwhAnfC4IUackvWNp/digP5AAo1/GTZ8Ws36s06PI6yCn7BzXo2SqZg1
# /f5MpqtUIv2A8cb/GOTZ6B5TTPGKhNdDNVyzIdBc+Y0r5Oj3WF21f2WdMj2pdspw
# Fz1Ixzo8++NgF2mQCcA1PV5FZzOXnX8xKTzuubVjeCx/EqouxWnsjeyxN0Bscr/O
# +zAZvpJdxYKYd3CSaafEiDyzXzBBZJbUqAOGjC7q7hZxIydgIagzsBd5VXxdDDLj
# LFF3ih2LzVrnpBDHwA+/fwLushdVKEQmm6La59PpyZHRx5sWK7W6VI6iTCxpCz3T
# N66HE9ptJb70nK5kNoLn7QRHTMDXJI0O52FaRi4YB0JVfsdSH/Llxp5RZQsiv8+Z
# ZnFUvhIznW0R3uI5Ep+RgveSB3CGdoJZeyzq8QyfPc/ZUEJOAzdnRSqIWqXD30xv
# ySLNXFJUImlvG7bGe3pdYEo2Zwdfp4WszvbIti5LbBOAvgjfcnWviKJBRoxNm9GZ
# 1mm6+6Y7StMaQZMbj4Td0/gAPPVafJsn4tOWF/JB+sjh0EHtGsTJZGtAuNq1B6Ph
# zxVqGJ160pxPgk7+R2BjsURBdnJ/qO8fsaofFTytZuV/gGFsWbUGzsg/DTGo0llZ
# zw2/R8ZOCBVLl1upDAZc/u+KRxpmi+iT6PE=
# SIG # End signature block

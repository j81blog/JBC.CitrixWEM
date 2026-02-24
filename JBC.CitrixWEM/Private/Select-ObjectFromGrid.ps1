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
# MIImdwYJKoZIhvcNAQcCoIImaDCCJmQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAv8tOBd8L6IRVL
# enT+iTyeHTfsEsvxwfx6l8GtjyejbKCCIAowggYUMIID/KADAgECAhB6I67aU2mW
# D5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUg
# U3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYD
# VQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPvIhKA
# VD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlBnwDE
# JuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv2eNm
# GiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7CQKf
# OUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLgzb1g
# bL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ1AzC
# s1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwUtrYE
# 2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYadtn03
# 4ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0jBBgw
# FoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1SgLqz
# YZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVUacah
# RoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQUn73
# 3qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M/SFj
# eCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7KyUJ
# Go1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/mSiSU
# ice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ1c6F
# ibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALOz1Uj
# b0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7HpNi/
# KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUufrV64
# EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ7l93
# 9bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5vVye
# fQIwggZFMIIELaADAgECAhAIMk+dt9qRb2Pk8qM8Xl1RMA0GCSqGSIb3DQEBCwUA
# MFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMu
# QS4xJDAiBgNVBAMTG0NlcnR1bSBDb2RlIFNpZ25pbmcgMjAyMSBDQTAeFw0yNDA0
# MDQxNDA0MjRaFw0yNzA0MDQxNDA0MjNaMGsxCzAJBgNVBAYTAk5MMRIwEAYDVQQH
# DAlTY2hpam5kZWwxIzAhBgNVBAoMGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5
# MSMwIQYDVQQDDBpKb2huIEJpbGxla2VucyBDb25zdWx0YW5jeTCCAaIwDQYJKoZI
# hvcNAQEBBQADggGPADCCAYoCggGBAMslntDbSQwHZXwFhmibivbnd0Qfn6sqe/6f
# os3pKzKxEsR907RkDMet2x6RRg3eJkiIr3TFPwqBooyXXgK3zxxpyhGOcuIqyM9J
# 28DVf4kUyZHsjGO/8HFjrr3K1hABNUszP0o7H3o6J31eqV1UmCXYhQlNoW9FOmRC
# 1amlquBmh7w4EKYEytqdmdOBavAD5Xq4vLPxNP6kyA+B2YTtk/xM27TghtbwFGKn
# u9Vwnm7dFcpLxans4ONt2OxDQOMA5NwgcUv/YTpjhq9qoz6ivG55NRJGNvUXsM3w
# 2o7dR6Xh4MuEGrTSrOWGg2A5EcLH1XqQtkF5cZnAPM8W/9HUp8ggornWnFVQ9/6M
# ga+ermy5wy5XrmQpN+x3u6tit7xlHk1Hc+4XY4a4ie3BPXG2PhJhmZAn4ebNSBwN
# Hh8z7WTT9X9OFERepGSytZVeEP7hgyptSLcuhpwWeR4QdBb7dV++4p3PsAUQVHFp
# wkSbrRTv4EiJ0Lcz9P1HPGFoHiFAQQIDAQABo4IBeDCCAXQwDAYDVR0TAQH/BAIw
# ADA9BgNVHR8ENjA0MDKgMKAuhixodHRwOi8vY2NzY2EyMDIxLmNybC5jZXJ0dW0u
# cGwvY2NzY2EyMDIxLmNybDBzBggrBgEFBQcBAQRnMGUwLAYIKwYBBQUHMAGGIGh0
# dHA6Ly9jY3NjYTIwMjEub2NzcC1jZXJ0dW0uY29tMDUGCCsGAQUFBzAChilodHRw
# Oi8vcmVwb3NpdG9yeS5jZXJ0dW0ucGwvY2NzY2EyMDIxLmNlcjAfBgNVHSMEGDAW
# gBTddF1MANt7n6B0yrFu9zzAMsBwzTAdBgNVHQ4EFgQUO6KtBpOBgmrlANVAnyiQ
# C6W6lJwwSwYDVR0gBEQwQjAIBgZngQwBBAEwNgYLKoRoAYb2dwIFAQQwJzAlBggr
# BgEFBQcCARYZaHR0cHM6Ly93d3cuY2VydHVtLnBsL0NQUzATBgNVHSUEDDAKBggr
# BgEFBQcDAzAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAEQsN8wg
# PMdWVkwHPPTN+jKpdns5AKVFjcn00psf2NGVVgWWNQBIQc9lEuTBWb54IK6Ga3hx
# QRZfnPNo5HGl73YLmFgdFQrFzZ1lnaMdIcyh8LTWv6+XNWfoyCM9wCp4zMIDPOs8
# LKSMQqA/wRgqiACWnOS4a6fyd5GUIAm4CuaptpFYr90l4Dn/wAdXOdY32UhgzmSu
# xpUbhD8gVJUaBNVmQaRqeU8y49MxiVrUKJXde1BCrtR9awXbqembc7Nqvmi60tYK
# lD27hlpKtj6eGPjkht0hHEsgzU0Fxw7ZJghYG2wXfpF2ziN893ak9Mi/1dmCNmor
# GOnybKYfT6ff6YTCDDNkod4egcMZdOSv+/Qv+HAeIgEvrxE9QsGlzTwbRtbm6gwY
# YcVBs/SsVUdBn/TSB35MMxRhHE5iC3aUTkDbceo/XP3uFhVL4g2JZHpFfCSu2TQr
# rzRn2sn07jfMvzeHArCOJgBW1gPqR3WrJ4hUxL06Rbg1gs9tU5HGGz9KNQMfQFQ7
# 0Wz7UIhezGcFcRfkIfSkMmQYYpsc7rfzj+z0ThfDVzzJr2dMOFsMlfj1T6l22GBq
# 9XQx0A4lcc5Fl9pRxbOuHHWFqIBD/BCEhwniOCySzqENd2N+oz8znKooSISStnkN
# aYXt6xblJF2dx9Dn89FK7d1IquNxOwt0tI5dMIIGYjCCBMqgAwIBAgIRAKQpO24e
# 3denNAiHrXpOtyQwDQYJKoZIhvcNAQEMBQAwVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSMzYwHhcNMjUwMzI3MDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjByMQswCQYDVQQGEwJHQjEXMBUGA1UECBMOV2VzdCBZb3Jrc2hpcmUxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEwMC4GA1UEAxMnU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBTaWduZXIgUjM2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEA04SV9G6kU3jyPRBLeBIHPNyUgVNnYayfsGOyYEXrn3+SkDYTLs1crcw/
# ol2swE1TzB2aR/5JIjKNf75QBha2Ddj+4NEPKDxHEd4dEn7RTWMcTIfm492TW22I
# 8LfH+A7Ehz0/safc6BbsNBzjHTt7FngNfhfJoYOrkugSaT8F0IzUh6VUwoHdYDpi
# ln9dh0n0m545d5A5tJD92iFAIbKHQWGbCQNYplqpAFasHBn77OqW37P9BhOASdmj
# p3IijYiFdcA0WQIe60vzvrk0HG+iVcwVZjz+t5OcXGTcxqOAzk1frDNZ1aw8nFhG
# EvG0ktJQknnJZE3D40GofV7O8WzgaAnZmoUn4PCpvH36vD4XaAF2CjiPsJWiY/j2
# xLsJuqx3JtuI4akH0MmGzlBUylhXvdNVXcjAuIEcEQKtOBR9lU4wXQpISrbOT8ux
# +96GzBq8TdbhoFcmYaOBZKlwPP7pOp5Mzx/UMhyBA93PQhiCdPfIVOCINsUY4U23
# p4KJ3F1HqP3H6Slw3lHACnLilGETXRg5X/Fp8G8qlG5Y+M49ZEGUp2bneRLZoyHT
# yynHvFISpefhBCV0KdRZHPcuSL5OAGWnBjAlRtHvsMBrI3AAA0Tu1oGvPa/4yeei
# Ayu+9y3SLC98gDVbySnXnkujjhIh+oaatsk/oyf5R2vcxHahajMCAwEAAaOCAY4w
# ggGKMB8GA1UdIwQYMBaAFF9Y7UwxeqJhQo1SgLqzYZcZojKbMB0GA1UdDgQWBBSI
# YYyhKjdkgShgoZsx0Iz9LALOTzAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIw
# ADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDBKBgNVHSAEQzBBMDUGDCsGAQQBsjEB
# AgEDCDAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZn
# gQwBBAIwSgYDVR0fBEMwQTA/oD2gO4Y5aHR0cDovL2NybC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUHVibGljVGltZVN0YW1waW5nQ0FSMzYuY3JsMHoGCCsGAQUFBwEBBG4w
# bDBFBggrBgEFBQcwAoY5aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVi
# bGljVGltZVN0YW1waW5nQ0FSMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2Nz
# cC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAYEAAoE+pIZyUSH5ZakuPVKK
# 4eWbzEsTRJOEjbIu6r7vmzXXLpJx4FyGmcqnFZoa1dzx3JrUCrdG5b//LfAxOGy9
# Ph9JtrYChJaVHrusDh9NgYwiGDOhyyJ2zRy3+kdqhwtUlLCdNjFjakTSE+hkC9F5
# ty1uxOoQ2ZkfI5WM4WXA3ZHcNHB4V42zi7Jk3ktEnkSdViVxM6rduXW0jmmiu71Z
# pBFZDh7Kdens+PQXPgMqvzodgQJEkxaION5XRCoBxAwWwiMm2thPDuZTzWp/gUFz
# i7izCmEt4pE3Kf0MOt3ccgwn4Kl2FIcQaV55nkjv1gODcHcD9+ZVjYZoyKTVWb4V
# qMQy/j8Q3aaYd/jOQ66Fhk3NWbg2tYl5jhQCuIsE55Vg4N0DUbEWvXJxtxQQaVR5
# xzhEI+BjJKzh3TQ026JxHhr2fuJ0mV68AluFr9qshgwS5SpN5FFtaSEnAwqZv3IS
# +mlG50rK7W3qXbWwi4hmpylUfygtYLEdLQukNEX1jiOKMIIGgjCCBGqgAwIBAgIQ
# NsKwvXwbOuejs902y8l1aDANBgkqhkiG9w0BAQwFADCBiDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYD
# VQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBS
# U0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMjEwMzIyMDAwMDAwWhcNMzgw
# MTE4MjM1OTU5WjBXMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1p
# dGVkMS4wLAYDVQQDEyVTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIFJvb3Qg
# UjQ2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAiJ3YuUVnnR3d6Lkm
# gZpUVMB8SQWbzFoVD9mUEES0QUCBdxSZqdTkdizICFNeINCSJS+lV1ipnW5ihkQy
# C0cRLWXUJzodqpnMRs46npiJPHrfLBOifjfhpdXJ2aHHsPHggGsCi7uE0awqKggE
# /LkYw3sqaBia67h/3awoqNvGqiFRJ+OTWYmUCO2GAXsePHi+/JUNAax3kpqstbl3
# vcTdOGhtKShvZIvjwulRH87rbukNyHGWX5tNK/WABKf+Gnoi4cmisS7oSimgHUI0
# Wn/4elNd40BFdSZ1EwpuddZ+Wr7+Dfo0lcHflm/FDDrOJ3rWqauUP8hsokDoI7D/
# yUVI9DAE/WK3Jl3C4LKwIpn1mNzMyptRwsXKrop06m7NUNHdlTDEMovXAIDGAvYy
# nPt5lutv8lZeI5w3MOlCybAZDpK3Dy1MKo+6aEtE9vtiTMzz/o2dYfdP0KWZwZIX
# bYsTIlg1YIetCpi5s14qiXOpRsKqFKqav9R1R5vj3NgevsAsvxsAnI8Oa5s2oy25
# qhsoBIGo/zi6GpxFj+mOdh35Xn91y72J4RGOJEoqzEIbW3q0b2iPuWLA911cRxgY
# 5SJYubvjay3nSMbBPPFsyl6mY4/WYucmyS9lo3l7jk27MAe145GWxK4O3m3gEFEI
# kv7kRmefDR7Oe2T1HxAnICQvr9sCAwEAAaOCARYwggESMB8GA1UdIwQYMBaAFFN5
# v1qqK0rPVIDh2JvAnfKyA2bLMB0GA1UdDgQWBBT2d2rdP/0BE/8WoWyCAi/QCj0U
# JTAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zATBgNVHSUEDDAKBggr
# BgEFBQcDCDARBgNVHSAECjAIMAYGBFUdIAAwUAYDVR0fBEkwRzBFoEOgQYY/aHR0
# cDovL2NybC51c2VydHJ1c3QuY29tL1VTRVJUcnVzdFJTQUNlcnRpZmljYXRpb25B
# dXRob3JpdHkuY3JsMDUGCCsGAQUFBwEBBCkwJzAlBggrBgEFBQcwAYYZaHR0cDov
# L29jc3AudXNlcnRydXN0LmNvbTANBgkqhkiG9w0BAQwFAAOCAgEADr5lQe1oRLjl
# ocXUEYfktzsljOt+2sgXke3Y8UPEooU5y39rAARaAdAxUeiX1ktLJ3+lgxtoLQhn
# 5cFb3GF2SSZRX8ptQ6IvuD3wz/LNHKpQ5nX8hjsDLRhsyeIiJsms9yAWnvdYOdEM
# q1W61KE9JlBkB20XBee6JaXx4UBErc+YuoSb1SxVf7nkNtUjPfcxuFtrQdRMRi/f
# InV/AobE8Gw/8yBMQKKaHt5eia8ybT8Y/Ffa6HAJyz9gvEOcF1VWXG8OMeM7Vy7B
# s6mSIkYeYtddU1ux1dQLbEGur18ut97wgGwDiGinCwKPyFO7ApcmVJOtlw9FVJxw
# /mL1TbyBns4zOgkaXFnnfzg4qbSvnrwyj1NiurMp4pmAWjR+Pb/SIduPnmFzbSN/
# G8reZCL4fvGlvPFk4Uab/JVCSmj59+/mB2Gn6G/UYOy8k60mKcmaAZsEVkhOFuoj
# 4we8CYyaR9vd9PGZKSinaZIkvVjbH/3nlLb0a7SBIkiRzfPfS9T+JesylbHa1LtR
# V9U/7m0q7Ma2CQ/t392ioOssXW7oKLdOmMBl14suVFBmbzrt5V5cQPnwtd3UOTpS
# 9oCG+ZZheiIvPgkDmA8FzPsnfXW5qHELB43ET7HHFHeRPRYrMBKjkb8/IN7Po0d0
# hQoF4TeMM+zYAJzoKQnVKOLg8pZVPT8wgga5MIIEoaADAgECAhEAmaOACiZVO2Wr
# 3G6EprPqOTANBgkqhkiG9w0BAQwFADCBgDELMAkGA1UEBhMCUEwxIjAgBgNVBAoT
# GVVuaXpldG8gVGVjaG5vbG9naWVzIFMuQS4xJzAlBgNVBAsTHkNlcnR1bSBDZXJ0
# aWZpY2F0aW9uIEF1dGhvcml0eTEkMCIGA1UEAxMbQ2VydHVtIFRydXN0ZWQgTmV0
# d29yayBDQSAyMB4XDTIxMDUxOTA1MzIxOFoXDTM2MDUxODA1MzIxOFowVjELMAkG
# A1UEBhMCUEwxITAfBgNVBAoTGEFzc2VjbyBEYXRhIFN5c3RlbXMgUy5BLjEkMCIG
# A1UEAxMbQ2VydHVtIENvZGUgU2lnbmluZyAyMDIxIENBMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAnSPPBDAjO8FGLOczcz5jXXp1ur5cTbq96y34vuTm
# flN4mSAfgLKTvggv24/rWiVGzGxT9YEASVMw1Aj8ewTS4IndU8s7VS5+djSoMcbv
# IKck6+hI1shsylP4JyLvmxwLHtSworV9wmjhNd627h27a8RdrT1PH9ud0IF+njvM
# k2xqbNTIPsnWtw3E7DmDoUmDQiYi/ucJ42fcHqBkbbxYDB7SYOouu9Tj1yHIohzu
# C8KNqfcYf7Z4/iZgkBJ+UFNDcc6zokZ2uJIxWgPWXMEmhu1gMXgv8aGUsRdaCtVD
# 2bSlbfsq7BiqljjaCun+RJgTgFRCtsuAEw0pG9+FA+yQN9n/kZtMLK+Wo837Q4QO
# ZgYqVWQ4x6cM7/G0yswg1ElLlJj6NYKLw9EcBXE7TF3HybZtYvj9lDV2nT8mFSkc
# SkAExzd4prHwYjUXTeZIlVXqj+eaYqoMTpMrfh5MCAOIG5knN4Q/JHuurfTI5XDY
# O962WZayx7ACFf5ydJpoEowSP07YaBiQ8nXpDkNrUA9g7qf/rCkKbWpQ5boufUnq
# 1UiYPIAHlezf4muJqxqIns/kqld6JVX8cixbd6PzkDpwZo4SlADaCi2JSplKShBS
# ND36E/ENVv8urPS0yOnpG4tIoBGxVCARPCg1BnyMJ4rBJAcOSnAWd18Jx5n858JS
# qPECAwEAAaOCAVUwggFRMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFN10XUwA
# 23ufoHTKsW73PMAywHDNMB8GA1UdIwQYMBaAFLahVDkCw6A/joq8+tT4HKbROg79
# MA4GA1UdDwEB/wQEAwIBBjATBgNVHSUEDDAKBggrBgEFBQcDAzAwBgNVHR8EKTAn
# MCWgI6Ahhh9odHRwOi8vY3JsLmNlcnR1bS5wbC9jdG5jYTIuY3JsMGwGCCsGAQUF
# BwEBBGAwXjAoBggrBgEFBQcwAYYcaHR0cDovL3N1YmNhLm9jc3AtY2VydHVtLmNv
# bTAyBggrBgEFBQcwAoYmaHR0cDovL3JlcG9zaXRvcnkuY2VydHVtLnBsL2N0bmNh
# Mi5jZXIwOQYDVR0gBDIwMDAuBgRVHSAAMCYwJAYIKwYBBQUHAgEWGGh0dHA6Ly93
# d3cuY2VydHVtLnBsL0NQUzANBgkqhkiG9w0BAQwFAAOCAgEAdYhYD+WPUCiaU58Q
# 7EP89DttyZqGYn2XRDhJkL6P+/T0IPZyxfxiXumYlARMgwRzLRUStJl490L94C9L
# GF3vjzzH8Jq3iR74BRlkO18J3zIdmCKQa5LyZ48IfICJTZVJeChDUyuQy6rGDxLU
# UAsO0eqeLNhLVsgw6/zOfImNlARKn1FP7o0fTbj8ipNGxHBIutiRsWrhWM2f8pXd
# d3x2mbJCKKtl2s42g9KUJHEIiLni9ByoqIUul4GblLQigO0ugh7bWRLDm0CdY9rN
# LqyA3ahe8WlxVWkxyrQLjH8ItI17RdySaYayX3PhRSC4Am1/7mATwZWwSD+B7eMc
# ZNhpn8zJ+6MTyE6YoEBSRVrs0zFFIHUR08Wk0ikSf+lIe5Iv6RY3/bFAEloMU+vU
# BfSouCReZwSLo8WdrDlPXtR0gicDnytO7eZ5827NS2x7gCBibESYkOh1/w1tVxTp
# V2Na3PR7nxYVlPu1JPoRZCbH86gc96UTvuWiOruWmyOEMLOGGniR+x+zPF/2DaGg
# K2W1eEJfo2qyrBNPvF7wuAyQfiFXLwvWHamoYtPZo0LHuH8X3n9C+xN4YaNjt2yw
# zOr+tKyEVAotnyU9vyEVOaIYMk3IeBrmFnn0gbKeTTyYeEEUz/Qwt4HOUBCrW602
# NCmvO1nm+/80nLy5r0AZvCQxaQ4xggXDMIIFvwIBATBqMFYxCzAJBgNVBAYTAlBM
# MSEwHwYDVQQKExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0Nl
# cnR1bSBDb2RlIFNpZ25pbmcgMjAyMSBDQQIQCDJPnbfakW9j5PKjPF5dUTANBglg
# hkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3
# DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEV
# MC8GCSqGSIb3DQEJBDEiBCDk2SBrAWUq98kqUSezvKGJuaRZ9thtuUKy8NI+Potd
# 2TANBgkqhkiG9w0BAQEFAASCAYBYQ7EdatRQTy7v1WxVAMh5nJJloLcLnUAETW0i
# 9VRtyTz/DGn2lKNQLBcKMXqcwWMYVMSf2kx4LYRVy3YaCSUukvpY0Y3spyURzCqh
# t34oTSk0jMRGZo1FKcdCxSv6VQBGNcIfoYb6gXEIfs2HXwQPuR/OOMZpZW4xmYMv
# 9OPwQhz2do4hLfjNp02Gdx2gt+2mxdqwz1umf+NXrafsVVswD5aC4FOC8oKjDr5a
# peLWnw0CvqdUZrsVgWAuLsG2PVXHD2mODT1NGRzwl7q/5q8WABgFpA6O037qJU2q
# E1swB5FQw9oMvgP1AhmkveX4sUsrAp/IPDrWWoDUcSUyzboI53WCzcZeF/7HHiBB
# wVwmX/mhnChFf0n7I+cdDSKDxxNogX8Z0Oz3AhJtvY9CacZ8jO0M0O1F//tlIc0d
# 9jUxmWQfgXm+8aVSZKX8SSkdhETNWV/QzjDvYahEWZrO3qrHMKad5u6ziYj4E2ER
# oX2XrcuNsUymczS2kBeHMOyQI6uhggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwC
# AQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQp
# O24e3denNAiHrXpOtyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAxMzAyMDQ2MTBaMD8GCSqGSIb3
# DQEJBDEyBDC9LPWGqcqBkWcGH3Mzj5KgNmFShvUIdPIjEO+C3/2PhxGNKzf69lRd
# dRI7r9aqkLowDQYJKoZIhvcNAQEBBQAEggIAHFODzVJeVbyr9RXit8JdIgFGKfmR
# DH1YUwvVMXGnmLCpXHKSN+X44alxhTsuXxOkvrFSBR19hHjJJ6q64+AfbNJY+p1t
# dWWtL8qijZy46uWT2kqjSATNgX7QE5lW0GbSGHym+EN8piR4diOyMyRxVFfu0CXr
# 8p9HREKhU5JvQqIZHRyH6PJeXCauo0T3P+3IxCJrEob+26pKCtDeOLYyFHEHbubB
# YDBqMZy0zQ1qFRI6ikbkoVwC4/U3AlVWKfbzLK7gx6pk7FtmU44OT4LP75rU3+Rj
# Zk3wy/X8iGH+fgiyZMd37OvMnR6PG+Q0ZJ8+bR0HGs8bKNKS7rhrsrs0tIROnkox
# HgKVT46RZRMcC/OtWSYsXQ9iotFPu8Av5bBilpmC14sjwo5ytykUwC5ln9cmWm3I
# pN7WASY7t6VBrT9H7oWxzg/1VjQMfaVGT/37JATNyOt8VCFtAhinuT2ziWDcfsVD
# O1Txo3KxXA2myCefwMigP9XeWvsHDhl99IXu+YSdhDBj0+vG+2sJjx2FqtT1n1s2
# degSPVd32JMCMwBxZZtyncwGdJGe1sHJML0TWq7kHb4SiJqj2aqKkzkCj44O5f1I
# i75BceNg6xRuKtQmcydOWjRtqP5vz1+xiDKD0Fhq5QJmTLT8xBuZo38nKSSvFakZ
# qp2IE9WOfxv3Bqg=
# SIG # End signature block

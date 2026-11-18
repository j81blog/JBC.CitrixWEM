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
        such as Select All/Deselect All buttons and minimum/maximum selection
        validation.

        With the ViewOnly switch the checkbox column and the selection controls are
        hidden, which turns the window into a read-only viewer. This is a usable
        alternative to Out-GridView on hosts where Out-GridView is unavailable, such
        as PowerShell 7 without the Microsoft.PowerShell.ConsoleGuiTools module, or
        Windows installations without the ISE components.

    .PARAMETER InputObject
        The collection of objects to display in the grid.
        Accepts pipeline input.

    .PARAMETER Title
        The title to display in the window title bar.
        Defaults to "Select Items".

    .PARAMETER Description
        The subtitle shown under the header inside the window.
        Defaults to a text matching the current mode.

    .PARAMETER ColumnsToShow
        An optional array of property names to display as columns.
        If not specified, all properties from the first object are displayed.

    .PARAMETER DetailsProperty
        The name of a property whose (usually long or multi-line) text is shown in an
        expandable details panel underneath the row instead of, or in addition to, a
        column. The panel appears when a row is selected. Excluded from the visible
        columns unless the same name is also explicitly listed in -ColumnsToShow.
        Its text is always searched by the global filter box.

    .PARAMETER MinSelection
        The minimum number of items that must be selected before OK can be clicked.
        Defaults to 0 (no minimum). Ignored when ViewOnly is used.

    .PARAMETER MaxSelection
        The maximum number of items that can be selected before OK can be clicked.
        Defaults to 0 (no maximum / unlimited). Ignored when ViewOnly is used.

        Note that this validates rather than blocks: the user can tick more items than
        MaxSelection, but OK stays disabled until the count is back within the limit.

    .PARAMETER ViewOnly
        Hides the checkbox column, the Select All / Deselect All buttons and the Cancel
        button, and turns the window into a read-only viewer with a single Close button.
        No objects are returned in this mode.

        NoSelection is an alias for this parameter.

    .EXAMPLE
        $selected = Get-Process | Select-Object -Property Name, Id, CPU | Select-ObjectFromGrid

        Displays all processes in a grid and returns the selected items.

    .EXAMPLE
        $users = Get-ADUser -Filter * -Properties DisplayName, EmailAddress
        $selected = $users | Select-ObjectFromGrid -Title "Select Users" -ColumnsToShow DisplayName, EmailAddress

        Displays AD users with only DisplayName and EmailAddress columns.

    .EXAMPLE
        $items | Select-ObjectFromGrid -MinSelection 1 -MaxSelection 5

        Requires at least 1 selection and allows maximum 5 selections.

    .EXAMPLE
        $entries | Select-ObjectFromGrid -Title "Log" -ColumnsToShow Timestamp, Message -DetailsProperty Details -ViewOnly

        Shows Timestamp and Message as columns; selecting a row expands a panel
        showing the entry's Details text underneath it.

    .EXAMPLE
        Get-Service | Select-Object -Property Name, Status, StartType | Select-ObjectFromGrid -Title "Services" -ViewOnly

        Displays the services in a read-only viewer without checkboxes, as an
        alternative to Out-GridView. Nothing is returned.

    .OUTPUTS
        PSCustomObject[]
        Returns an array of the selected input objects, or $null if cancelled.
        Returns nothing when ViewOnly is used.

    .NOTES
        Function  : Select-ObjectFromGrid
        Author    : John Billekens
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 2026.728.908
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
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [string[]]$ColumnsToShow,

        [Parameter(Mandatory = $false)]
        [string]$DetailsProperty,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MinSelection = 0,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxSelection = 0,

        [Parameter(Mandatory = $false)]
        [Alias('NoSelection')]
        [switch]$ViewOnly
    )

    begin {
        $allItems = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            $allItems.Add($item)
        }
    }

    end {
        if ($allItems.Count -eq 0) {
            Write-Warning "No items to display."
            return $null
        }

        if ($MinSelection -gt 0 -and $MaxSelection -gt 0 -and $MinSelection -gt $MaxSelection) {
            throw "MinSelection ($MinSelection) cannot be greater than MaxSelection ($MaxSelection)."
        }

        # ShowDialog() requires STA; MTA throws unhandled on the dispatcher and kills the process.
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
            throw "Select-ObjectFromGrid requires a single-threaded apartment (STA) thread to show its window. " + `
                "Restart PowerShell with 'powershell.exe -STA' or 'pwsh -STA', or run this from a host that already uses STA (e.g. the default Windows PowerShell 5.1 console)."
        }

        # Load WPF assemblies
        Add-Type -AssemblyName PresentationFramework
        Add-Type -AssemblyName PresentationCore
        Add-Type -AssemblyName WindowsBase

        # Determine columns to display
        $firstItem = $allItems[0]
        if ($ColumnsToShow -and $ColumnsToShow.Count -gt 0) {
            $columns = @($ColumnsToShow)
        } else {
            $columns = @($firstItem.PSObject.Properties.Name)
        }

        # Details property gets its own panel unless the caller explicitly kept it in ColumnsToShow.
        if ($DetailsProperty -and -not ($ColumnsToShow -and $ColumnsToShow -contains $DetailsProperty)) {
            $columns = @($columns | Where-Object { $_ -ne $DetailsProperty })
        }

        if ($columns.Count -eq 0) {
            Write-Warning "No columns to display."
            return $null
        }

        if (-not $PSBoundParameters.ContainsKey('Description')) {
            $Description = if ($ViewOnly) {
                "Review the items below and close the window when you are done."
            } else {
                "Manage your selection and confirm your choice."
            }
        }

        # Column names are built in code, not via XAML string interpolation.
        $escapeXml = {
            param([string]$Text)
            [System.Security.SecurityElement]::Escape($Text)
        }

        # The checkbox column and the selection controls only exist in selection mode.
        if ($ViewOnly) {
            $checkBoxColumnXaml = ""
            $selectionPanelVisibility = "Collapsed"
            $cancelButtonVisibility = "Collapsed"
            $okButtonText = "Close"
            $headerText = & $escapeXml $Title
        } else {
            $checkBoxColumnXaml = @"
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
"@
            $selectionPanelVisibility = "Visible"
            $cancelButtonVisibility = "Visible"
            $okButtonText = "OK"
            $headerText = & $escapeXml $Title
        }

        $titleXml = & $escapeXml $Title
        $descriptionXml = & $escapeXml $Description

        # Create the XAML for the window
        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$titleXml"
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
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
            <Setter Property="Padding" Value="18,11"/>
            <Setter Property="MinWidth" Value="120"/>
            <Setter Property="MinHeight" Value="38"/>
            <Setter Property="Margin" Value="6,0,0,0"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBg"
                               Background="{TemplateBinding Background}"
                               BorderBrush="Transparent"
                               BorderThickness="1"
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
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonBg" Property="BorderBrush" Value="#93C5FD"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#232E45"/>
                                <Setter Property="Foreground" Value="#5B6B85"/>
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
                        <Border x:Name="GhostBg"
                               Background="{TemplateBinding Background}"
                               BorderBrush="{TemplateBinding BorderBrush}"
                               BorderThickness="{TemplateBinding BorderThickness}"
                               CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center"
                                             VerticalAlignment="Center"
                                             RecognizesAccessKey="True"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#22304C"/>
                                <Setter TargetName="GhostBg" Property="BorderBrush" Value="#3A4C6E"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#151D31"/>
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="GhostBg" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
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
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <!-- Small round "clear" button living inside the filter box; the implicit Button style
             would give it an accent fill and a 120px MinWidth, so it needs its own template. -->
        <Style x:Key="FilterClearButton" TargetType="Button">
            <Setter Property="Width" Value="16"/>
            <Setter Property="Height" Value="16"/>
            <Setter Property="MinWidth" Value="0"/>
            <Setter Property="MinHeight" Value="0"/>
            <Setter Property="Margin" Value="0"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Cursor" Value="Arrow"/>
            <Setter Property="ToolTip" Value="Clear this filter"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ClearBg"
                               Background="{TemplateBinding Background}"
                               CornerRadius="8"
                               SnapsToDevicePixels="True">
                            <Path x:Name="ClearGlyph"
                                 Data="M0,0 L7,7 M7,0 L0,7"
                                 Stroke="#94A3B8"
                                 StrokeThickness="1.4"
                                 StrokeStartLineCap="Round"
                                 StrokeEndLineCap="Round"
                                 HorizontalAlignment="Center"
                                 VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ClearBg" Property="Background" Value="#2D3B54"/>
                                <Setter TargetName="ClearGlyph" Property="Stroke" Value="#F8FAFC"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ClearBg" Property="Background" Value="#3A4C6E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Per-column filter TextBox, rounded to match the global filter box -->
        <Style x:Key="ColumnFilterBox" TargetType="TextBox">
            <Setter Property="Background" Value="#0F172A"/>
            <Setter Property="BorderBrush" Value="#2D3B54"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextBrush}"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="Margin" Value="0,6,0,0"/>
            <Setter Property="MinWidth" Value="80"/>
            <Setter Property="Cursor" Value="IBeam"/>
            <!-- Header style sets HorizontalContentAlignment=Stretch; inherited it offsets the
                 caret from the placeholder text. Pin both so hint and caret share an origin. -->
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="FilterBorder"
                               Background="{TemplateBinding Background}"
                               BorderBrush="{TemplateBinding BorderBrush}"
                               BorderThickness="{TemplateBinding BorderThickness}"
                               CornerRadius="6">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <!-- Margin 10,4: TextBox Padding (8) plus the border and the
                                     TextBoxView's own 1px inset, so the hint starts exactly on
                                     the caret position rather than 2px left of it. -->
                                <TextBlock x:Name="FilterHint"
                                          Grid.Column="0"
                                          Text="Filter"
                                          Foreground="#4B5A75"
                                          Margin="10,4,8,4"
                                          HorizontalAlignment="Left"
                                          VerticalAlignment="Center"
                                          IsHitTestVisible="False"
                                          Visibility="Collapsed"/>
                                <!-- No Margin binding: the inner TextBoxView already applies the
                                     TextBox Padding itself, so binding Margin to Padding as well
                                     would inset the caret twice and push it right of the hint. -->
                                <ScrollViewer x:Name="PART_ContentHost"
                                             Grid.Column="0"
                                             HorizontalAlignment="Stretch"
                                             VerticalAlignment="Center"/>
                                <Button x:Name="PART_ClearFilter"
                                       Grid.Column="1"
                                       Style="{StaticResource FilterClearButton}"
                                       Margin="2,0,5,0"
                                       VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="FilterBorder" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                            <!-- Empty box: show the hint, hide the clear button. -->
                            <Trigger Property="Text" Value="">
                                <Setter TargetName="FilterHint" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="PART_ClearFilter" Property="Visibility" Value="Collapsed"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Thin dark scrollbars -->
        <Style x:Key="GridThumb" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="ThumbBorder" Background="#3B4E75" CornerRadius="5"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ThumbBorder" Property="Background" Value="#4A5F8C"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="ThumbBorder" Property="Background" Value="#5A6F9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="GridRepeatButton" TargetType="RepeatButton">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Rectangle Fill="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="12"/>
            <Setter Property="MinWidth" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid Background="Transparent">
                            <Border Background="#131D33" CornerRadius="5" Margin="2,0"/>
                            <Track Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource GridRepeatButton}" Command="ScrollBar.PageUpCommand"/>
                                </Track.DecreaseRepeatButton>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Style="{StaticResource GridRepeatButton}" Command="ScrollBar.PageDownCommand"/>
                                </Track.IncreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource GridThumb}" Width="8" Margin="2,0"/>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Height" Value="12"/>
                    <Setter Property="MinHeight" Value="12"/>
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="MinWidth" Value="0"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="ScrollBar">
                                <Grid Background="Transparent">
                                    <Border Background="#131D33" CornerRadius="5" Margin="0,2"/>
                                    <Track Name="PART_Track" IsDirectionReversed="False">
                                        <Track.DecreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource GridRepeatButton}" Command="ScrollBar.PageLeftCommand"/>
                                        </Track.DecreaseRepeatButton>
                                        <Track.IncreaseRepeatButton>
                                            <RepeatButton Style="{StaticResource GridRepeatButton}" Command="ScrollBar.PageRightCommand"/>
                                        </Track.IncreaseRepeatButton>
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource GridThumb}" Height="8" Margin="0,2"/>
                                        </Track.Thumb>
                                    </Track>
                                </Grid>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="DataGridRow">
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Margin" Value="0,0,0,2"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#16233C"/>
                </Trigger>
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
                <!-- Right-click gives the row keyboard focus without selecting it; default
                     WPF chrome for a focused-but-unselected row is a light system color. -->
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="DataGridCell">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="14,12"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Style.Triggers>
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="BorderThickness" Value="1"/>
                    <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                </Trigger>
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

        <Style x:Key="ContextMenuItemDarkStyle" TargetType="MenuItem">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="MenuItem">
                        <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" CornerRadius="5">
                            <ContentPresenter ContentSource="Header" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="{StaticResource AccentBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ContextMenuDarkStyle" TargetType="ContextMenu">
            <Setter Property="Background" Value="{StaticResource CardBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource CardBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="4"/>
            <Setter Property="HasDropShadow" Value="False"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="ItemContainerStyle" Value="{StaticResource ContextMenuItemDarkStyle}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ContextMenu">
                        <Border Background="{StaticResource CardBrush}"
                               BorderBrush="{TemplateBinding BorderBrush}"
                               BorderThickness="{TemplateBinding BorderThickness}"
                               CornerRadius="8"
                               SnapsToDevicePixels="True">
                            <Border.Effect>
                                <DropShadowEffect Color="#33000000" BlurRadius="14" ShadowDepth="0" Opacity="0.35"/>
                            </Border.Effect>
                            <StackPanel IsItemsHost="True" Margin="{TemplateBinding Padding}"/>
                        </Border>
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
            <TextBlock Text="$headerText"
                      FontSize="24"
                      FontWeight="Bold"
                      Foreground="{StaticResource TextBrush}"/>
            <TextBlock Text="$descriptionXml"
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

                <!-- Filter and selection actions -->
                <Grid Grid.Row="0" Margin="0,0,0,12">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal" HorizontalAlignment="Left">
                        <Border Name="borderFilter"
                               Background="#0F172A"
                               BorderBrush="#2D3B54"
                               BorderThickness="1"
                               CornerRadius="8"
                               Padding="10,6"
                               MinWidth="280">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid Grid.Column="0" Width="15" Height="15" Margin="2,0,8,0" VerticalAlignment="Center">
                                    <Ellipse Width="10" Height="10"
                                            Stroke="#64748B"
                                            StrokeThickness="1.6"
                                            HorizontalAlignment="Left"
                                            VerticalAlignment="Top"/>
                                    <Line X1="9.5" Y1="9.5" X2="13.5" Y2="13.5"
                                         Stroke="#64748B"
                                         StrokeThickness="1.6"
                                         StrokeEndLineCap="Round"/>
                                </Grid>
                                <TextBlock Grid.Column="1"
                                          Name="txtFilterHint"
                                          Text="Search all columns..."
                                          Foreground="#64748B"
                                          VerticalAlignment="Center"
                                          IsHitTestVisible="False"
                                          Margin="2,0,0,0"/>
                                <TextBox Grid.Column="1"
                                        Name="txtFilter"
                                        Background="Transparent"
                                        BorderThickness="0"
                                        Foreground="{StaticResource TextBrush}"
                                        CaretBrush="{StaticResource TextBrush}"
                                        VerticalAlignment="Center"/>
                            </Grid>
                        </Border>
                        <Button Name="btnClearFilters"
                               Content="Clear filters"
                               Style="{StaticResource GhostButton}"/>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Orientation="Horizontal">
                        <StackPanel Name="pnlSelectionActions"
                                   Orientation="Horizontal"
                                   Visibility="$selectionPanelVisibility">
                            <Button Name="btnSelectAll" Content="Select All" Style="{StaticResource GhostButton}" Margin="0,0,10,0"/>
                            <Button Name="btnDeselectAll" Content="Deselect All" Style="{StaticResource GhostButton}"/>
                        </StackPanel>
                        <TextBlock Name="txtSelectionInfo"
                                  VerticalAlignment="Center"
                                  Margin="16,0,0,0"
                                  FontSize="12"
                                  Foreground="{StaticResource TextSubtleBrush}"/>
                    </StackPanel>
                </Grid>

                <!-- Data Grid -->
                <DataGrid Grid.Row="1"
                         Name="dataGrid"
                         AutoGenerateColumns="False"
                         CanUserAddRows="False"
                         CanUserDeleteRows="False"
                         CanUserSortColumns="False"
                         SelectionMode="Extended"
                         SelectionUnit="FullRow"
                         IsReadOnly="True"
                         AlternationCount="2"
                         EnableRowVirtualization="True"
                         EnableColumnVirtualization="False"
                         VirtualizingPanel.IsVirtualizing="True"
                         VirtualizingPanel.VirtualizationMode="Recycling"
                         VirtualizingPanel.ScrollUnit="Pixel"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto">
                    <DataGrid.RowDetailsTemplate>
                        <DataTemplate>
                            <Border x:Name="DetailsBorder"
                                   Background="#0D1526"
                                   BorderBrush="#24324D"
                                   BorderThickness="0,1,0,1"
                                   Padding="18,10">
                                <TextBox Text="{Binding _DetailsText, Mode=OneWay}"
                                        IsReadOnly="True"
                                        BorderThickness="0"
                                        Background="Transparent"
                                        Foreground="#CBD5E1"
                                        FontFamily="Consolas"
                                        FontSize="12"
                                        TextWrapping="Wrap"/>
                            </Border>
                            <DataTemplate.Triggers>
                                <DataTrigger Binding="{Binding _DetailsText}" Value="">
                                    <Setter TargetName="DetailsBorder" Property="Visibility" Value="Collapsed"/>
                                </DataTrigger>
                            </DataTemplate.Triggers>
                        </DataTemplate>
                    </DataGrid.RowDetailsTemplate>
                    <DataGrid.Columns>
$checkBoxColumnXaml
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
            <Button Name="btnCancel"
                   Content="Cancel"
                   Style="{StaticResource GhostButton}"
                   IsCancel="True"
                   Margin="0,0,10,0"
                   Visibility="$cancelButtonVisibility"/>
            <Button Name="btnOK" Content="$okButtonText" IsDefault="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

        # Ordered hashtable; Add-Member per property is far slower.
        $wrappedItems = [System.Collections.Generic.List[object]]::new($allItems.Count)
        foreach ($item in $allItems) {
            $properties = [ordered]@{}
            if (-not $ViewOnly) {
                $properties['IsSelected'] = $false
            }
            foreach ($col in $columns) {
                $value = $item.$col
                if ($null -ne $value) {
                    # Unwrap PSObject; WPF's sort comparer can't compare the wrapper.
                    $value = $value.PSObject.BaseObject
                }
                $properties[$col] = $value
            }
            if ($DetailsProperty) {
                $detailsValue = $item.$DetailsProperty
                $properties['_DetailsText'] = if ($null -eq $detailsValue) { '' } else { [string]$detailsValue }
            }
            $properties['_OriginalItem'] = $item
            $wrappedItems.Add([PSCustomObject]$properties)
        }

        # Parse XAML
        try {
            $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
            try {
                $window = [System.Windows.Markup.XamlReader]::Load($reader)
            } finally {
                $reader.Close()
            }
        } catch [System.Windows.Markup.XamlParseException] {
            throw "Failed to build the grid window: $($_.Exception.Message)"
        }

        # Get controls
        $dataGrid = $window.FindName("dataGrid")
        $dataGrid.RowDetailsVisibilityMode = if ($DetailsProperty) {
            [System.Windows.Controls.DataGridRowDetailsVisibilityMode]::VisibleWhenSelected
        } else {
            [System.Windows.Controls.DataGridRowDetailsVisibilityMode]::Collapsed
        }
        $btnSelectAll = $window.FindName("btnSelectAll")
        $btnDeselectAll = $window.FindName("btnDeselectAll")
        $btnOK = $window.FindName("btnOK")
        $btnCancel = $window.FindName("btnCancel")
        $txtSelectionInfo = $window.FindName("txtSelectionInfo")
        $txtStatus = $window.FindName("txtStatus")
        $txtFilter = $window.FindName("txtFilter")
        $txtFilterHint = $window.FindName("txtFilterHint")
        $btnClearFilters = $window.FindName("btnClearFilters")
        $borderFilter = $window.FindName("borderFilter")
        $columnFilterBoxStyle = $window.FindResource("ColumnFilterBox")
        $accentBrush = $window.FindResource("AccentBrush")
        $defaultFilterBorderBrush = $borderFilter.BorderBrush

        # Focus highlight, matches per-column filter box style.
        $txtFilter.Add_GotFocus({
            $borderFilter.BorderBrush = $accentBrush
        }.GetNewClosure())
        $txtFilter.Add_LostFocus({
            $borderFilter.BorderBrush = $defaultFilterBorderBrush
        }.GetNewClosure())

        # Columns built in code; arbitrary property names could break XAML binding paths.
        $cellStyle = [System.Windows.Style]::new([System.Windows.Controls.TextBlock])
        $cellStyle.Setters.Add([System.Windows.Setter]::new(
                [System.Windows.Controls.TextBlock]::VerticalAlignmentProperty,
                [System.Windows.VerticalAlignment]::Center))
        $cellStyle.Setters.Add([System.Windows.Setter]::new(
                [System.Windows.FrameworkElement]::MarginProperty,
                [System.Windows.Thickness]::new(10, 6, 10, 6)))
        $cellStyle.Setters.Add([System.Windows.Setter]::new(
                [System.Windows.Controls.TextBlock]::ForegroundProperty,
                $window.FindResource("TextBrush")))

        # A collection view gives filtering/sorting without touching the backing list.
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($wrappedItems)

        $state = @{
            DialogResult     = $null
            SelectedItems    = @()
            WrappedItems     = $wrappedItems
            Columns          = $columns
            View             = $view
            DataGrid         = $dataGrid
            Window           = $window
            MinSelection     = $MinSelection
            MaxSelection     = $MaxSelection
            ViewOnly         = [bool]$ViewOnly
            TxtSelectionInfo = $txtSelectionInfo
            TxtStatus        = $txtStatus
            TxtFilterHint    = $txtFilterHint
            BtnOK            = $btnOK
            # Guards against queueing multiple deferred recounts.
            UpdatePending    = $false
            ColumnFilters    = @{}
            ColumnFilterBoxes = @{}
            SortArrows       = @{}
            PopupCloseTicks  = @{}
            DetailsKey       = if ($DetailsProperty) { '_DetailsText' } else { $null }
            SortColumn       = $null
            SortDirection    = 0
        }

        $state.UpdateSelection = {
            # Counted from the data; checkbox events also fire on container
            # regeneration (refresh, scrolling), so they cannot drive a counter.
            $selectedCount = 0
            foreach ($item in $state.WrappedItems) {
                if ($item.IsSelected) { $selectedCount++ }
            }
            $totalCount = $state.WrappedItems.Count

            $infoText = "$selectedCount of $totalCount selected"
            if ($state.MinSelection -gt 0 -or $state.MaxSelection -gt 0) {
                $constraints = @()
                if ($state.MinSelection -gt 0) { $constraints += "min: $($state.MinSelection)" }
                if ($state.MaxSelection -gt 0) { $constraints += "max: $($state.MaxSelection)" }
                $infoText += " (" + ($constraints -join ", ") + ")"
            }
            $visibleCount = $state.View.Count
            if ($visibleCount -lt $totalCount) {
                $infoText += " - showing $visibleCount of $totalCount"
            }
            $state.TxtSelectionInfo.Text = $infoText

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
            $state.TxtStatus.Foreground = if ($valid) {
                [System.Windows.Media.Brushes]::Gray
            } else {
                [System.Windows.Media.Brushes]::Red
            }
            $state.BtnOK.IsEnabled = $valid
        }.GetNewClosure()

        # Coalesced recount, deferred until the checkbox bindings have written back.
        $state.RequestSelectionUpdate = {
            if ($state.UpdatePending) { return }
            $state.UpdatePending = $true
            # Re-bound locally, see the popup handler below for why.
            $stateRef = $state
            [void]$state.Window.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [System.Action]{
                    $stateRef.UpdatePending = $false
                    & $stateRef.UpdateSelection
                }.GetNewClosure())
        }.GetNewClosure()

        # ViewOnly status text (no selection counter).
        $state.UpdateFilterStatus = {
            $totalCount = $state.WrappedItems.Count
            $visibleCount = $state.View.Count
            if ($visibleCount -lt $totalCount) {
                $state.TxtSelectionInfo.Text = "showing $visibleCount of $totalCount item(s)"
            } else {
                $state.TxtSelectionInfo.Text = "$totalCount item(s)"
            }
        }.GetNewClosure()

        # Reapplies filter and refreshes status text.
        $state.RefreshFilterState = {
            $anyActive = (-not [string]::IsNullOrEmpty($state.Filter))
            if (-not $anyActive) {
                foreach ($needle in $state.ColumnFilters.Values) {
                    if (-not [string]::IsNullOrEmpty($needle)) { $anyActive = $true; break }
                }
            }

            if ($anyActive) {
                $state.View.Filter = $state.FilterPredicate
            } else {
                $state.View.Filter = $null
            }
            $state.View.Refresh()

            if ($state.ViewOnly) {
                & $state.UpdateFilterStatus
            } else {
                & $state.UpdateSelection
            }
        }.GetNewClosure()

        # 3-state: unsorted -> ascending -> descending -> unsorted. Single column only.
        $state.ApplySort = {
            param([string]$ColumnName)

            if ($state.SortColumn -eq $ColumnName) {
                $state.SortDirection = $state.SortDirection + 1
                if ($state.SortDirection -gt 2) { $state.SortDirection = 0 }
            } else {
                $state.SortColumn = $ColumnName
                $state.SortDirection = 1
            }
            if ($state.SortDirection -eq 0) { $state.SortColumn = $null }

            $state.View.SortDescriptions.Clear()
            if ($state.SortColumn) {
                $direction = if ($state.SortDirection -eq 1) {
                    [System.ComponentModel.ListSortDirection]::Ascending
                } else {
                    [System.ComponentModel.ListSortDirection]::Descending
                }
                try {
                    [void]$state.View.SortDescriptions.Add([System.ComponentModel.SortDescription]::new($state.SortColumn, $direction))
                } catch {
                    # Non-comparable values.
                    $state.View.SortDescriptions.Clear()
                    $state.SortColumn = $null
                    $state.SortDirection = 0
                    $state.TxtStatus.Text = "Column '$ColumnName' contains values that cannot be sorted."
                }
            }

            foreach ($name in $state.SortArrows.Keys) {
                $arrow = $state.SortArrows[$name]
                if ($name -eq $state.SortColumn -and $state.SortDirection -eq 1) {
                    $arrow.Text = [char]0x25B2
                } elseif ($name -eq $state.SortColumn -and $state.SortDirection -eq 2) {
                    $arrow.Text = [char]0x25BC
                } else {
                    $arrow.Text = ""
                }
            }
        }.GetNewClosure()

        $funnelIdleBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x64, 0x74, 0x8B))
        $funnelIdleBrush.Freeze()
        $popupBorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x2D, 0x3B, 0x54))
        $popupBorderBrush.Freeze()

        # Header: title (sort) + funnel icon (filter popup).
        foreach ($col in $columns) {
            $colName = $col

            $binding = [System.Windows.Data.Binding]::new()
            $binding.Path = [System.Windows.PropertyPath]::new($colName)
            $binding.Mode = [System.Windows.Data.BindingMode]::OneWay

            $column = [System.Windows.Controls.DataGridTextColumn]::new()
            $column.Binding = $binding
            $column.IsReadOnly = $true
            $column.CanUserSort = $false
            # CanUserSort is off; SortMemberPath just carries the column name to the Click handler.
            $column.SortMemberPath = $colName
            $column.Width = [System.Windows.Controls.DataGridLength]::Auto
            $column.ElementStyle = $cellStyle

            # Title + sort arrow.
            $titleBlock = [System.Windows.Controls.TextBlock]::new()
            $titleBlock.Text = $colName
            $titleBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

            $arrowBlock = [System.Windows.Controls.TextBlock]::new()
            $arrowBlock.Text = ""
            $arrowBlock.Margin = [System.Windows.Thickness]::new(4, 0, 0, 0)
            $arrowBlock.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $arrowBlock.FontSize = 10
            $arrowBlock.Foreground = $window.FindResource("AccentBrush")
            $state.SortArrows[$colName] = $arrowBlock

            $titleRow = [System.Windows.Controls.StackPanel]::new()
            $titleRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
            [void]$titleRow.Children.Add($titleBlock)
            [void]$titleRow.Children.Add($arrowBlock)

            # Filter popup trigger.
            $funnel = [System.Windows.Shapes.Path]::new()
            $funnel.Data = [System.Windows.Media.Geometry]::Parse("M0,0 H12 L7,5.5 V10.5 L5,9 V5.5 Z")
            $funnel.Fill = $funnelIdleBrush
            $funnel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

            $funnelHost = [System.Windows.Controls.Border]::new()
            $funnelHost.Background = [System.Windows.Media.Brushes]::Transparent
            $funnelHost.Padding = [System.Windows.Thickness]::new(5, 3, 5, 3)
            $funnelHost.Margin = [System.Windows.Thickness]::new(2, 0, 0, 0)
            $funnelHost.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $funnelHost.Cursor = [System.Windows.Input.Cursors]::Hand
            $funnelHost.ToolTip = "Filter this column"
            $funnelHost.Child = $funnel

            $filterBox = [System.Windows.Controls.TextBox]::new()
            $filterBox.Style = $columnFilterBoxStyle
            $filterBox.Width = 180
            $filterBox.Margin = [System.Windows.Thickness]::new(0)
            $state.ColumnFilters[$colName] = $null
            $state.ColumnFilterBoxes[$colName] = $filterBox
            $state.PopupCloseTicks[$colName] = 0L

            $popupBorder = [System.Windows.Controls.Border]::new()
            $popupBorder.Background = $window.FindResource("CardBrush")
            $popupBorder.BorderBrush = $popupBorderBrush
            $popupBorder.BorderThickness = [System.Windows.Thickness]::new(1)
            $popupBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $popupBorder.Padding = [System.Windows.Thickness]::new(10)
            $popupBorder.Child = $filterBox

            # StaysOpen=True: a StaysOpen=False popup takes mouse capture and treats the
            # still-pending MouseUp of the opening click as an outside click, closing it on
            # button release. Dismissal is handled explicitly via LostKeyboardFocus below.
            $popup = [System.Windows.Controls.Primitives.Popup]::new()
            $popup.AllowsTransparency = $true
            $popup.StaysOpen = $true
            $popup.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
            $popup.PlacementTarget = $funnelHost
            $popup.VerticalOffset = 4
            $popup.Child = $popupBorder

            $popup.Add_Closed({
                $state.PopupCloseTicks[$colName] = [DateTime]::UtcNow.Ticks
            }.GetNewClosure())

            # Clicking away moves keyboard focus off the filter box; that is the dismiss signal.
            $filterBox.Add_LostKeyboardFocus({
                $popup.IsOpen = $false
            }.GetNewClosure())

            # Header captures mouse on down; only Preview reaches here. Handled=true blocks sort.
            # Time guard stops the click that dismissed the popup from immediately reopening it.
            $funnelHost.Add_PreviewMouseLeftButtonDown({
                $_.Handled = $true
                if ($popup.IsOpen) {
                    $popup.IsOpen = $false
                } elseif (([DateTime]::UtcNow.Ticks - $state.PopupCloseTicks[$colName]) -gt 3000000) {
                    # Re-bound locally: GetNewClosure() on a scriptblock nested inside an
                    # already-closed scriptblock does not reliably inherit the outer closure's
                    # captured variables, so $popup/$filterBox must be re-captured here at call time.
                    $popupToOpen = $popup
                    $filterBoxToFocus = $filterBox
                    # Deferred to Input priority so the box is focusable once the popup is realized.
                    [void]$state.Window.Dispatcher.BeginInvoke(
                        [System.Windows.Threading.DispatcherPriority]::Input,
                        [System.Action]{
                            $popupToOpen.IsOpen = $true
                            [void]$filterBoxToFocus.Focus()
                        }.GetNewClosure())
                }
            }.GetNewClosure())

            $filterBox.Add_KeyDown({
                if ($_.Key -eq [System.Windows.Input.Key]::Escape -or $_.Key -eq [System.Windows.Input.Key]::Enter) {
                    $popup.IsOpen = $false
                }
            }.GetNewClosure())

            # Template is only applied once the box is loaded, so the button exists from here on.
            # Clearing Text drives TextChanged, which resets the filter state and funnel color.
            # Tag guards against a second Loaded (popup reopen) stacking duplicate handlers.
            #
            # PreviewMouseLeftButtonDown, not Click: pressing the button moves focus off the
            # filter box, whose LostKeyboardFocus closes the popup and destroys the button
            # before the mouse-up that would raise Click, so Click never fires. Handled=true
            # keeps focus on the box, so the popup stays open after clearing.
            $filterBox.Add_Loaded({
                $clearButton = $filterBox.Template.FindName("PART_ClearFilter", $filterBox)
                if ($clearButton -and $null -eq $clearButton.Tag) {
                    $clearButton.Tag = "wired"
                    # Re-bound locally for the same reason as the funnel handler above: this
                    # scriptblock is nested inside an already-closed one, so $filterBox must be
                    # re-captured here or it is null when the click fires.
                    $boxToClear = $filterBox
                    $clearButton.Add_PreviewMouseLeftButtonDown({
                        $_.Handled = $true
                        $boxToClear.Clear()
                        [void]$boxToClear.Focus()
                    }.GetNewClosure())
                }
            }.GetNewClosure())

            $filterBox.Add_TextChanged({
                $text = $filterBox.Text
                if ([string]::IsNullOrWhiteSpace($text)) {
                    $state.ColumnFilters[$colName] = $null
                    $funnel.Fill = $funnelIdleBrush
                } else {
                    $state.ColumnFilters[$colName] = $text
                    $funnel.Fill = $accentBrush
                }
                & $state.RefreshFilterState
            }.GetNewClosure())

            $headerPanel = [System.Windows.Controls.StackPanel]::new()
            $headerPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
            [void]$headerPanel.Children.Add($titleRow)
            [void]$headerPanel.Children.Add($funnelHost)
            [void]$headerPanel.Children.Add($popup)

            $column.Header = $headerPanel

            $dataGrid.Columns.Add($column)
        }

        $btnClearFilters.Add_Click({
            $txtFilter.Text = ""
            foreach ($box in $state.ColumnFilterBoxes.Values) {
                $box.Text = ""
            }
        }.GetNewClosure())

        # Header captures mouse; child MouseUp handlers never fire. Use header's own Click.
        $dataGrid.AddHandler(
            [System.Windows.Controls.Primitives.DataGridColumnHeader]::ClickEvent,
            [System.Windows.RoutedEventHandler] {
                $header = $_.OriginalSource
                if ($header -is [System.Windows.Controls.Primitives.DataGridColumnHeader] -and
                    $null -ne $header.Column -and
                    -not [string]::IsNullOrEmpty($header.Column.SortMemberPath)) {
                    & $state.ApplySort $header.Column.SortMemberPath
                }
            }.GetNewClosure()
        )

        # Ctrl+C copies the focused cell; context menu adds explicit Copy Cell / Copy Row.
        $copyCellMenuItem = [System.Windows.Controls.MenuItem]::new()
        $copyCellMenuItem.Header = "Copy Cell"
        $copyRowMenuItem = [System.Windows.Controls.MenuItem]::new()
        $copyRowMenuItem.Header = "Copy Row"
        $gridContextMenu = [System.Windows.Controls.ContextMenu]::new()
        # Code-created ContextMenu is reparented under a Popup adorner; implicit
        # Window.Resources styling by TargetType does not reliably apply there.
        $gridContextMenu.Style = $window.FindResource("ContextMenuDarkStyle")
        [void]$gridContextMenu.Items.Add($copyCellMenuItem)
        [void]$gridContextMenu.Items.Add($copyRowMenuItem)
        $dataGrid.ContextMenu = $gridContextMenu

        # Right-click must not change row selection (it would toggle the details panel).
        # Move CurrentCell to the cell under the pointer so Copy Cell/Row still target it.
        $dataGrid.AddHandler(
            [System.Windows.Controls.DataGridCell]::PreviewMouseRightButtonDownEvent,
            [System.Windows.Input.MouseButtonEventHandler] {
                $cellElement = $_.OriginalSource
                while ($cellElement -and -not ($cellElement -is [System.Windows.Controls.DataGridCell])) {
                    $cellElement = [System.Windows.Media.VisualTreeHelper]::GetParent($cellElement)
                }
                if ($cellElement -and $cellElement.Column) {
                    $state.DataGrid.CurrentCell = [System.Windows.Controls.DataGridCellInfo]::new($cellElement.DataContext, $cellElement.Column)
                }
                $_.Handled = $true
            }.GetNewClosure()
        )

        $state.CopyCurrentCell = {
            $cell = $state.DataGrid.CurrentCell
            if ($null -eq $cell.Column -or $null -eq $cell.Item -or [string]::IsNullOrEmpty($cell.Column.SortMemberPath)) { return }
            $value = $cell.Item.($cell.Column.SortMemberPath)
            [System.Windows.Clipboard]::SetText($(if ($null -eq $value) { '' } else { $value.ToString() }))
        }.GetNewClosure()

        $state.CopyCurrentRow = {
            $item = $state.DataGrid.CurrentCell.Item
            if ($null -eq $item) { $item = $state.DataGrid.SelectedItem }
            if ($null -eq $item) { return }
            $values = foreach ($col in $state.Columns) { $item.$col }
            [System.Windows.Clipboard]::SetText($values -join "`t")
        }.GetNewClosure()

        $copyCellMenuItem.Add_Click({ & $state.CopyCurrentCell }.GetNewClosure())
        $copyRowMenuItem.Add_Click({ & $state.CopyCurrentRow }.GetNewClosure())

        $dataGrid.Add_PreviewKeyDown({
            if ($_.Key -eq [System.Windows.Input.Key]::C -and
                ($_.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                & $state.CopyCurrentCell
                $_.Handled = $true
            }
        }.GetNewClosure())

        $dataGrid.ItemsSource = $view

        # Case-insensitive substring. Global: any column. Per-column: AND, own column only.
        $state.Filter = $null
        $state.FilterPredicate = [Predicate[object]] {
            $row = $args[0]

            $needle = $state.Filter
            if (-not [string]::IsNullOrEmpty($needle)) {
                $globalMatch = $false
                foreach ($col in $state.Columns) {
                    $value = $row.$col
                    if ($null -ne $value -and $value.ToString().IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $globalMatch = $true
                        break
                    }
                }
                if (-not $globalMatch -and $state.DetailsKey) {
                    $value = $row.($state.DetailsKey)
                    if ($null -ne $value -and $value.ToString().IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $globalMatch = $true
                    }
                }
                if (-not $globalMatch) { return $false }
            }

            foreach ($col in $state.Columns) {
                $colNeedle = $state.ColumnFilters[$col]
                if ([string]::IsNullOrEmpty($colNeedle)) { continue }
                $value = $row.$col
                if ($null -eq $value -or $value.ToString().IndexOf($colNeedle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    return $false
                }
            }

            return $true
        }.GetNewClosure()

        $txtFilter.Add_TextChanged({
            $text = $txtFilter.Text
            $state.TxtFilterHint.Visibility = if ([string]::IsNullOrEmpty($text)) {
                [System.Windows.Visibility]::Visible
            } else {
                [System.Windows.Visibility]::Collapsed
            }

            if ([string]::IsNullOrWhiteSpace($text)) {
                $state.Filter = $null
            } else {
                $state.Filter = $text
            }
            & $state.RefreshFilterState
        }.GetNewClosure())

        if (-not $ViewOnly) {
            & $state.UpdateSelection

            # Visible rows only; the items carry no change notification, so the
            # grid needs an explicit refresh to redraw the checkboxes.
            $state.SetAllVisible = {
                param([bool]$Value)
                foreach ($item in $state.View) {
                    $item.IsSelected = $Value
                }
                $state.DataGrid.Items.Refresh()
                & $state.UpdateSelection
            }.GetNewClosure()

            $btnSelectAll.Add_Click({
                & $state.SetAllVisible $true
            }.GetNewClosure())

            $btnDeselectAll.Add_Click({
                & $state.SetAllVisible $false
            }.GetNewClosure())

            $dataGrid.AddHandler(
                [System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent,
                [System.Windows.RoutedEventHandler] {
                    & $state.RequestSelectionUpdate
                }.GetNewClosure()
            )

            $dataGrid.AddHandler(
                [System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent,
                [System.Windows.RoutedEventHandler] {
                    & $state.RequestSelectionUpdate
                }.GetNewClosure()
            )

            $btnOK.Add_Click({
                $selected = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $state.WrappedItems) {
                    if ($item.IsSelected) {
                        $selected.Add($item._OriginalItem)
                    }
                }
                $state.DialogResult = $true
                $state.SelectedItems = $selected.ToArray()
                $state.Window.Close()
            }.GetNewClosure())

            $btnCancel.Add_Click({
                $state.DialogResult = $false
                $state.Window.Close()
            }.GetNewClosure())
        } else {
            $txtSelectionInfo.Text = "$($wrappedItems.Count) item(s)"

            $btnOK.Add_Click({
                $state.Window.Close()
            }.GetNewClosure())
        }

        [void]$window.ShowDialog()

        if ($ViewOnly) {
            return
        }

        if ($state.DialogResult -eq $true) {
            return $state.SelectedItems
        } else {
            return $null
        }
    }
}

# SIG # Begin signature block
# MII6AgYJKoZIhvcNAQcCoII58zCCOe8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCCkDnsqOeOMWXz
# q/1taOZtPi+PQ2O3MVspRtJshvvUqKCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbAMIIEqKADAgECAhMzAAxah1Vq
# R2NpPKqSAAAADFqHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBBT0MgQ0EgMDMwHhcNMjYxMTE3MDE0NjAwWhcNMjYxMTIw
# MDE0NjAwWjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAkxAgXhorpiKQSF8LYykP38Cn
# DqcRYwHiCpWdAwxYxPR3BuZdTQgkNwy4exDN21zE78rhWrQcnBU+ERBPdRZxHAez
# vyAk7hs2tZm2G+iqgv9+aFf2h1YWeZM1o6gTcCk+CGUddzjUid7B0n9iCUitHfTd
# Ac2DAcLOVQc2eFpOLhgKD2ABbSL7iQPlaHKq1YTmAlnQsovojDlwjCtfJhVFKsBy
# bz4QDT/t6L2J02WG7MJ4Ty2mMi2Ncsq8Jcx1Y91Ab/6TkO3rrLqCV8S2ajZpDKxG
# NzkznH55Uy7a/pSUHIg181hcjx2hkHMhzPeTzbzW5rH5x6SZxti1nRoXfyfna0jN
# iiC5S1IbMgucg3GJ9TQ4McfrO56WbxFJF9QSI1X7dPEPArfabnxwaGXHSnTFMvL6
# A3Mrusbxng9AcAqogWeGtQRZj22ATFAXA+GWKQu+BcZkBRmIiMNaRqx54+iINJAS
# BVv/DLFa+CPoEhf0YgLA1DUfsJ4CpcEewQ0iA3wzAgMBAAGjggHTMIIBzzAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA6BgNVHSUEMzAxBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYZKwYBBAGCN2HK9PELgrHSgxH33KNOluu6MTAdBgNVHQ4EFgQU
# a7vPo3rl7uOyvSVDXOGHQlRWLWEwHwYDVR0jBBgwFoAUpEMMf3ZapYXnPo0oDwwX
# okVpcMYwZwYDVR0fBGAwXjBcoFqgWIZWaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwQU9D
# JTIwQ0ElMjAwMy5jcmwwdAYIKwYBBQUHAQEEaDBmMGQGCCsGAQUFBzAChlhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElE
# JTIwVmVyaWZpZWQlMjBDUyUyMEFPQyUyMENBJTIwMDMuY3J0MFQGA1UdIARNMEsw
# SQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wDQYJKoZIhvcNAQEMBQADggIBAKw0
# 3tsE8NphE+cpQtl7MPVz2Lv/qNHE+9Dw0KCFiM2HvRQdRgKQnUq9xpUSvSXLUNEh
# 0MKKRUXalgTz2hNFHk2NyDb10kfq8osU6AOMuZcQEsPsF1wNlexQ/+qZMQN17euD
# d3SSXCJVX5dw7Y7o6Vx95hEaAd+at0DKiueNnKnZzNwPKbRQCQ6FOaOyv8+ueAP5
# om3MoA/dJxsdqKh6oCHx7NljNTOp4bm1E6gDjoB9kjcfm7tVi3fL/A10FDeJwio8
# COhmmx1Ue2i8yNMCyqj7R/dKRlgW/4l69dwI3jxR5kMY/S1V2gqySQTtzRJR8f3x
# JUGidbYUlFb7K51NiakJ62M8xrNL4kjdsOagr+kdxykY78iXNAtFY+R0o7m4T+6S
# wiYnP8eFQe8OqUPHy8N8ifhuKMnfMdHA0sHlE+PFvYOm6Ttc93sJhXD0iFEUjDgg
# 324CHYF6v4rnhn4+5RIH9BTPeOu1ZY9W9U7fa/zCo7dRLQdvxwTaG+rNen2Uj+Hp
# 2NnFkiB/iJD8/FCOp4WFSyIPII/O9em6W1wKxw75e2ABzXc4L4jDRPNY83rO9+q7
# YC4glbGah7Uqf8cLfT+SmOQVFTwQUy33lQ36Y0ltblETR6LEv2rWJybXyckwvh2k
# 4tHQmsuVqMT8F4ScBucZjdMeehoZZOQH8rPApYOiMIIGwDCCBKigAwIBAgITMwAM
# WodVakdjaTyqkgAAAAxahzANBgkqhkiG9w0BAQwFADBaMQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3Nv
# ZnQgSUQgVmVyaWZpZWQgQ1MgQU9DIENBIDAzMB4XDTI2MTExNzAxNDYwMFoXDTI2
# MTEyMDAxNDYwMFowgYMxCzAJBgNVBAYTAk5MMRYwFAYDVQQIEw1Ob29yZC1CcmFi
# YW50MRIwEAYDVQQHEwlTY2hpam5kZWwxIzAhBgNVBAoTGkpvaG4gQmlsbGVrZW5z
# IENvbnN1bHRhbmN5MSMwIQYDVQQDExpKb2huIEJpbGxla2VucyBDb25zdWx0YW5j
# eTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAJMQIF4aK6YikEhfC2Mp
# D9/Apw6nEWMB4gqVnQMMWMT0dwbmXU0IJDcMuHsQzdtcxO/K4Vq0HJwVPhEQT3UW
# cRwHs78gJO4bNrWZthvoqoL/fmhX9odWFnmTNaOoE3ApPghlHXc41InewdJ/YglI
# rR303QHNgwHCzlUHNnhaTi4YCg9gAW0i+4kD5WhyqtWE5gJZ0LKL6Iw5cIwrXyYV
# RSrAcm8+EA0/7ei9idNlhuzCeE8tpjItjXLKvCXMdWPdQG/+k5Dt66y6glfEtmo2
# aQysRjc5M5x+eVMu2v6UlByINfNYXI8doZBzIcz3k8281uax+cekmcbYtZ0aF38n
# 52tIzYoguUtSGzILnINxifU0ODHH6zuelm8RSRfUEiNV+3TxDwK32m58cGhlx0p0
# xTLy+gNzK7rG8Z4PQHAKqIFnhrUEWY9tgExQFwPhlikLvgXGZAUZiIjDWkaseePo
# iDSQEgVb/wyxWvgj6BIX9GICwNQ1H7CeAqXBHsENIgN8MwIDAQABo4IB0zCCAc8w
# DAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwOgYDVR0lBDMwMQYKKwYBBAGC
# N2EBAAYIKwYBBQUHAwMGGSsGAQQBgjdhyvTxC4Kx0oMR99yjTpbrujEwHQYDVR0O
# BBYEFGu7z6N65e7jsr0lQ1zhh0JUVi1hMB8GA1UdIwQYMBaAFKRDDH92WqWF5z6N
# KA8MF6JFaXDGMGcGA1UdHwRgMF4wXKBaoFiGVmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDUyUy
# MEFPQyUyMENBJTIwMDMuY3JsMHQGCCsGAQUFBwEBBGgwZjBkBggrBgEFBQcwAoZY
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQl
# MjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBBT0MlMjBDQSUyMDAzLmNydDBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMA0GCSqGSIb3DQEBDAUAA4IC
# AQCsNN7bBPDaYRPnKULZezD1c9i7/6jRxPvQ8NCghYjNh70UHUYCkJ1KvcaVEr0l
# y1DRIdDCikVF2pYE89oTRR5Njcg29dJH6vKLFOgDjLmXEBLD7BdcDZXsUP/qmTED
# de3rg3d0klwiVV+XcO2O6OlcfeYRGgHfmrdAyornjZyp2czcDym0UAkOhTmjsr/P
# rngD+aJtzKAP3ScbHaioeqAh8ezZYzUzqeG5tROoA46AfZI3H5u7VYt3y/wNdBQ3
# icIqPAjoZpsdVHtovMjTAsqo+0f3SkZYFv+JevXcCN48UeZDGP0tVdoKskkE7c0S
# UfH98SVBonW2FJRW+yudTYmpCetjPMazS+JI3bDmoK/pHccpGO/IlzQLRWPkdKO5
# uE/uksImJz/HhUHvDqlDx8vDfIn4bijJ3zHRwNLB5RPjxb2Dpuk7XPd7CYVw9IhR
# FIw4IN9uAh2Ber+K54Z+PuUSB/QUz3jrtWWPVvVO32v8wqO3US0Hb8cE2hvqzXp9
# lI/h6djZxZIgf4iQ/PxQjqeFhUsiDyCPzvXpultcCscO+XtgAc13OC+Iw0TzWPN6
# zvfqu2AuIJWxmoe1Kn/HC30/kpjkFRU8EFMt95UN+mNJbW5RE0eixL9q1icm18nJ
# ML4dpOLR0JrLlajE/BeEnAbnGY3THnoaGWTkB/KzwKWDojCCBygwggUQoAMCAQIC
# EzMAAAAYDeuRVamKAJgAAAAAABgwDQYJKoZIhvcNAQEMBQAwYzELMAkGA1UEBhMC
# VVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjE0MDIGA1UEAxMrTWlj
# cm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2lnbmluZyBQQ0EgMjAyMTAeFw0yNjAz
# MjYxODExMzJaFw0zMTAzMjYxODExMzJaMFoxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJRCBW
# ZXJpZmllZCBDUyBBT0MgQ0EgMDMwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQDIgNpgNFaiif2VWeWP5I6PnFXxJ/lB37fJR55GCvR7GLZBMkBijbiKVwgp
# BI3xM5nf484znH/qncJ+OCq6y3jgnQW+R8Zd7U+7LjlrmcskalzSQ0ghMxEpnBW8
# /HHs2V8ZJzQk6HP+SDsbvsL7LdlH/eO2l4mknhDBwr0Z/Q966TvEth5b8kCxj1vq
# iV4YNthLGRqZR9u2fK/yBMWu83p6O4uo2Edg++gEew5IL7vnnnKFqmSh/R9vPJy3
# WF1YcZewAUx8sXZNUnx3ZhVg59l2LpitPiwzE6FMqIsqaEvVe3MzuFd2a/uWDZH6
# VbDyUiRK78mIg1DQYA9zDEyyBFcNI+nxVSzglvL6u7PRuNqgcV3sf6ELxw89ysQM
# /Z4R1hRFWXRpyOWKKAKtfBHTk0UnNiPcxmLMMYs8jeUjOidfVPjTIry/UVwnwxdl
# kK85cZfBEMYZ/DBNOwdomP459Y1n8izKkbhsa+p4lw+cQVxATBFx9ggR79HhryT7
# HDmpPLvkJvBZ4wW4CW32UT2SMyDe28nIOU3m+hfHlVeKcLBQcym5VoRDjIcCVI7u
# qgGW2PNME0cfei8zCwCy6HCsssJWFS7eg/YbFhnATJcyWfMrkNuAbMfMN8Npg8cr
# S6jVVowyD0GG5zdgi+uQVcSK/638mA1xEYK3pnIoQgO09uuDBwIDAQABo4IB3DCC
# AdgwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBSk
# Qwx/dlqlhec+jSgPDBeiRWlwxjBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9z
# aXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAU2UEpsA8PY2zvadf1zSmepEhqMOYwcAYDVR0f
# BGkwZzBloGOgYYZfaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENvZGUlMjBTaWduaW5nJTIwUENB
# JTIwMjAyMS5jcmwwfQYIKwYBBQUHAQEEcTBvMG0GCCsGAQUFBzAChmFodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElEJTIw
# VmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3J0MA0GCSqG
# SIb3DQEBDAUAA4ICAQBxxyBW+X6mhdRiSwD9PMMWcGUAnx5/QUwnNvZdFGEX+4DR
# DIr9WCh4C87wHtw+lg1D3uzK10DstPX0LFLBFAC3vWMYX4ImXwoLhoR0xlN8mUdo
# rJ3bgnpCJWuI1531Z1rCwPuUrSkBxfOIGDk3p2ECb3Ho/xHi5PRSR/OUrWuQHwXi
# aXMTuXu3IRLezwVkZpFmNwYRD57R9Nx2F/yM7tzOY0Hh0hGCaYEK38/6FrS0SXad
# XWyDUCfn5XOGACRjUCnHx+JQUG0f4SHD+iblpAI0gl+ZHnVmdXXxHTZeTa0CYCIh
# FxKP2922s0g6zLmeiV13LWUmtt/UF7TrWXpMi2/0UNniaDoH7rnPGRV5xVX8uXy4
# sZii4aswzqPM7Y7+mzcranqZ8EjZk5gjLhQ3A2sZaprlOu8CaRmyfcIiVH7zVfgA
# vm81MWXFziAf7my7QOvnyEFPGddq8MSfPtfRyw/Uq3uH6KpoaJNIfPYH6fceZSi5
# 3Rat1A9grExq3ROjhhSpTcchuBItAMNVPxoKNbUm+iR/X3XkL+9WQginjyHe+hXL
# clY8vAGXFD1p40PqMIpAYsmEJBFKW9df4//1N5oQDr/FY9IBJl/oSS979i5rtT7N
# Zz9KvYraCPRBGs0QCy+sWvgQa0coM70QJVLeVwmSxUO/0od0w9Qry7bSLrxGoDCC
# B54wggWGoAMCAQICEzMAAAAHh6M0o3uljhwAAAAAAAcwDQYJKoZIhvcNAQEMBQAw
# dzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjFI
# MEYGA1UEAxM/TWljcm9zb2Z0IElkZW50aXR5IFZlcmlmaWNhdGlvbiBSb290IENl
# cnRpZmljYXRlIEF1dGhvcml0eSAyMDIwMB4XDTIxMDQwMTIwMDUyMFoXDTM2MDQw
# MTIwMTUyMFowYzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjE0MDIGA1UEAxMrTWljcm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2ln
# bmluZyBQQ0EgMjAyMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALLw
# wK8ZiCji3VR6TElsaQhVCbRS/3pK+MHrJSj3Zxd3KU3rlfL3qrZilYKJNqztA9OQ
# acr1AwoNcHbKBLbsQAhBnIB34zxf52bDpIO3NJlfIaTE/xrweLoQ71lzCHkD7A4A
# s1Bs076Iu+mA6cQzsYYH/Cbl1icwQ6C65rU4V9NQhNUwgrx9rGQ//h890Q8JdjLL
# w0nV+ayQ2Fbkd242o9kH82RZsH3HEyqjAB5a8+Ae2nPIPc8sZU6ZE7iRrRZywRmr
# KDp5+TcmJX9MRff241UaOBs4NmHOyke8oU1TYrkxh+YeHgfWo5tTgkoSMoayqoDp
# HOLJs+qG8Tvh8SnifW2Jj3+ii11TS8/FGngEaNAWrbyfNrC69oKpRQXY9bGH6jn9
# NEJv9weFxhTwyvx9OJLXmRGbAUXN1U9nf4lXezky6Uh/cgjkVd6CGUAf0K+Jw+GE
# /5VpIVbcNr9rNE50Sbmy/4RTCEGvOq3GhjITbCa4crCzTTHgYYjHs1NbOc6brH+e
# KpWLtr+bGecy9CrwQyx7S/BfYJ+ozst7+yZtG2wR461uckFu0t+gCwLdN0A6cFtS
# RtR8bvxVFyWwTtgMMFRuBa3vmUOTnfKLsLefRaQcVTgRnzeLzdpt32cdYKp+dhr2
# ogc+qM6K4CBI5/j4VFyC4QFeUP2YAidLtvpXRRo3AgMBAAGjggI1MIICMTAOBgNV
# HQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNlBKbAPD2Ns
# 72nX9c0pnqRIajDmMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsGAQUFBwIBFjNo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5o
# dG0wGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAf
# BgNVHSMEGDAWgBTIftJqhSobyhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHeg
# dYZzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUl
# MjBBdXRob3JpdHklMjAyMDIwLmNybDCBwwYIKwYBBQUHAQEEgbYwgbMwgYEGCCsG
# AQUFBzAChnVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRp
# ZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcnQwLQYIKwYBBQUHMAGGIWh0dHA6
# Ly9vbmVvY3NwLm1pY3Jvc29mdC5jb20vb2NzcDANBgkqhkiG9w0BAQwFAAOCAgEA
# fyUqnv7Uq+rdZgrbVyNMul5skONbhls5fccPlmIbzi+OwVdPQ4H55v7VOInnmezQ
# EeW4LqK0wja+fBznANbXLB0KrdMCbHQpbLvG6UA/Xv2pfpVIE1CRFfNF4XKO8XYE
# a3oW8oVH+KZHgIQRIwAbyFKQ9iyj4aOWeAzwk+f9E5StNp5T8FG7/VEURIVWArbA
# zPt9ThVN3w1fAZkF7+YU9kbq1bCR2YD+MtunSQ1Rft6XG7b4e0ejRA7mB2IoX5hN
# h3UEauY0byxNRG+fT2MCEhQl9g2i2fs6VOG19CNep7SquKaBjhWmirYyANb0RJSL
# WjinMLXNOAga10n8i9jqeprzSMU5ODmrMCJE12xS/NWShg/tuLjAsKP6SzYZ+1Ry
# 358ZTFcx0FS/mx2vSoU8s8HRvy+rnXqyUJ9HBqS0DErVLjQwK8VtsBdekBmdTbQV
# oCgPCqr+PDPB3xajYnzevs7eidBsM71PINK2BoE2UfMwxCCX3mccFgx6UsQeRSdV
# VVNSyALQe6PT12418xon2iDGE81OGCreLzDcMAZnrUAx4XQLUz6ZTl65yPUiOh3k
# 7Yww94lDf+8oG2oZmDh5O1Qe38E+M3vhKwmzIeoB1dVLlz4i3IpaDcR+iuGjH2Td
# aC1ZOmBXiCRKJLj4DT2uhJ04ji+tHD6n58vhavFIrmcxghcyMIIXLgIBATBxMFox
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzAp
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBBT0MgQ0EgMDMCEzMADFqH
# VWpHY2k8qpIAAAAMWocwDQYJYIZIAWUDBAIBBQCgXjAQBgorBgEEAYI3AgEMMQIw
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQgHngM
# 9gAk2+hx95NamSvKC5l5KjmK8bzCiPp5u1mtLdowDQYJKoZIhvcNAQEBBQAEggGA
# XvKsidunJ+D9fPN7BmzrqaXByN9QEu2TEgv5BCzZIxSO9MLoxWJcFCNeofSgWOe1
# R48gQmc+bbfewLXTyDmzRMrqMmBP1rhm56rg5hRrIQsoMHkJNLGV96u+TLZErRtU
# /YMuVy0yWJ4EnG1pKp8h/TPqOA7N1pP5QUQmDVnxLfvvguQWrdPOwY+ymEOq0pcV
# t4CZxuscL1kL//CWRjAh6LhEZbRbnpe2Kw+Cgb1CMFePpxro+8zGthm7uzBwJhp4
# CmTnqvAAfZQVMeHpOEz8AJYbd/fPdeRwcri+CX2NYnnEpJXX3ca1LP14STtLUMNR
# +XT0QRDzJpRoS/LNYMjMAVEJM1h11AQtjNtT9dORzMjeJ78JPG03bXBE+yQkCUzt
# GY8bvdiMxgQNC3H6e0Z5+81ICC2Y4IW9oAZOVlNP6T2wq1Paee0kubMEM4s0pmIW
# IJPc9hrMDAi1r/otqyT5jHUpIfilKV0/QVdyCmYH7TRYP/5hv7PWqL1nmWL39Oj+
# oYIUsjCCFK4GCisGAQQBgjcDAwExghSeMIIUmgYJKoZIhvcNAQcCoIIUizCCFIcC
# AQMxDzANBglghkgBZQMEAgEFADCCAWoGCyqGSIb3DQEJEAEEoIIBWQSCAVUwggFR
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIIY5/LVU5+oIZlJqoeTm
# rQwMviSa7KC6SjMvyjNK6A2xAgZq80t/3BwYEzIwMjYxMTE4MTM0MjI3LjgwNlow
# BIACAfSggemkgeYwgeMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjQ5MUEtMDVFMC1EOTQ3MTUwMwYD
# VQQDEyxNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0
# eaCCDykwggeCMIIFaqADAgECAhMzAAAABeXPD/9mLsmHAAAAAAAFMA0GCSqGSIb3
# DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24g
# Um9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAyMDAeFw0yMDExMTkyMDMyMzFa
# Fw0zNTExMTkyMDQyMzFaMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAnnznUmP94MWfBX1jtQYioxwe1+eXM9ETBb1lRkd3kcFdcG9/sqtDlwxKoVIc
# aqDb+omFio5DHC4RBcbyQHjXCwMk/l3TOYtgoBjxnG/eViS4sOx8y4gSq8Zg49RE
# Af5huXhIkQRKe3Qxs8Sgp02KHAznEa/Ssah8nWo5hJM1xznkRsFPu6rfDHeZeG1W
# a1wISvlkpOQooTULFm809Z0ZYlQ8Lp7i5F9YciFlyAKwn6yjN/kR4fkquUWfGmMo
# pNq/B8U/pdoZkZZQbxNlqJOiBGgCWpx69uKqKhTPVi3gVErnc/qi+dR8A2MiAz0k
# N0nh7SqINGbmw5OIRC0EsZ31WF3Uxp3GgZwetEKxLms73KG/Z+MkeuaVDQQheang
# OEMGJ4pQZH55ngI0Tdy1bi69INBV5Kn2HVJo9XxRYR/JPGAaM6xGl57Ei95HUw9N
# V/uC3yFjrhc087qLJQawSC3xzY/EXzsT4I7sDbxOmM2rl4uKK6eEpurRduOQ2hTk
# mG1hSuWYBunFGNv21Kt4N20AKmbeuSnGnsBCd2cjRKG79+TX+sTehawOoxfeOO/j
# R7wo3liwkGdzPJYHgnJ54UxbckF914AqHOiEV7xTnD1a69w/UTxwjEugpIPMIIE6
# 7SFZ2PMo27xjlLAHWW3l1CEAFjLNHd3EQ79PUr8FUXetXr0CAwEAAaOCAhswggIX
# MA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUa2ko
# OjUvSGNAz3vYr0npPtk92yEwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUH
# AgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0
# b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMA
# dQBiAEMAQTAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFMh+0mqFKhvKGZgE
# ByfPUBBPaKiiMIGEBgNVHR8EfTB7MHmgd6B1hnNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNh
# dGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3Js
# MIGUBggrBgEFBQcBAQSBhzCBhDCBgQYIKwYBBQUHMAKGdWh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBW
# ZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAy
# MDIwLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAX4h2x35ttVoVdedMeGj6TuHYRJkl
# FaW4sTQ5r+k77iB79cSLNe+GzRjv4pVjJviceW6AF6ycWoEYR0LYhaa0ozJLU5Yi
# +LCmcrdovkl53DNt4EXs87KDogYb9eGEndSpZ5ZM74LNvVzY0/nPISHz0Xva71Qj
# D4h+8z2XMOZzY7YQ0Psw+etyNZ1CesufU211rLslLKsO8F2aBs2cIo1k+aHOhrw9
# xw6JCWONNboZ497mwYW5EfN0W3zL5s3ad4Xtm7yFM7Ujrhc0aqy3xL7D5FR2J7x9
# cLWMq7eb0oYioXhqV2tgFqbKHeDick+P8tHYIFovIP7YG4ZkJWag1H91KlELGWi3
# SLv10o4KGag42pswjybTi4toQcC/irAodDW8HNtX+cbz0sMptFJK+KObAnDFHEsu
# kxD+7jFfEV9Hh/+CSxKRsmnuiovCWIOb+H7DRon9TlxydiFhvu88o0w35JkNbJxT
# k4MhF/KgaXn0GxdH8elEa2Imq45gaa8D+mTm8LWVydt4ytxYP/bqjN49D9NZ81co
# E6aQWm88TwIf4R4YZbOpMKN0CyejaPNN41LGXHeCUMYmBx3PkP8ADHD1J2Cr/6tj
# uOOCztfp+o9Nc+ZoIAkpUcA/X2gSMkgHAPUvIdtoSAHEUKiBhI6JQivRepyvWcl+
# JYbYbBh7pmgAXVswggefMIIFh6ADAgECAhMzAAAAWvYNZ4yF7d0IAAAAAABaMA0G
# CSqGSIb3DQEBDAUAMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVz
# dGFtcGluZyBDQSAyMDIwMB4XDTI2MDEwODE4NTkwM1oXDTI3MDEwNzE4NTkwM1ow
# geMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
# JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMe
# blNoaWVsZCBUU1MgRVNOOjQ5MUEtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3Nv
# ZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAO/0O0eWjgUb9rnHcQLRdfWPN4H+91a3Ynla
# P46E1m4uD+JKx6csWMStX79fxLJUAqHJqQWE19UlNMhS9jEB32dAJ4yuWsHyUuM+
# dphjDz4E5jl4gYGZEmaOrKvNt+KqlFayyg/oTg3BlLRu4aBq8668A5qlHcfsuh6D
# dSqFID1ixJFZzHrZFG1iGBG7U1Bn2ONLDo7jbwX5rMcPduTAUw/c7M3WhSxQBuZp
# Qiz8RQGKIqCKfIxgQkKdzpCpU0SWQOE/DgTXbz3c15KMRCdkGlL2zb+lnuSV4sse
# Qm3qflZiZckLyn2xJI8ZXDkq+Ig+b/rsPPIfI8di228WvK1j67JXpyeVCaSUO9Er
# zlLnTrnjQkeXVQIp73xuVBVrmvoTf/v4a7MnrmuKSyIXc5vJUHEGB345+O8omFt1
# w8b+Xg9D9PKIRqDPEv7HRk0C+Yvxu8FvHJvSocSIZK+v/FmKFOipYnpP76yAmJNn
# yheucShOgk8QiU53USn/+AyMb7xW905gZnyNqb29HeVdQ175pDHJGEz8Cx5wiHeV
# liGz5hABucFDylR9z3LSTmB6+3ZuIxeG9BZS46P6ANPkuVuD5m8wgc7GLLzg73Cs
# DF09ukt8Uf8dTcMBX3ro+7/k9M6Xt8WPG7IL9v/4DvyMY03tkb9Y9Ri6HWavXRPY
# RCUePspPAgMBAAGjggHLMIIBxzAdBgNVHQ4EFgQUjmOyQ6twMcP1ZbRytJxI4fnX
# mcIwHwYDVR0jBBgwFoAUa2koOjUvSGNAz3vYr0npPtk92yEwbAYDVR0fBGUwYzBh
# oF+gXYZbaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9z
# b2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNy
# bDB5BggrBgEFBQcBAQRtMGswaQYIKwYBBQUHMAKGXWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIw
# VGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBmBgNVHSAEXzBdMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wCAYGZ4EMAQQCMA0GCSqG
# SIb3DQEBDAUAA4ICAQCAlM8r+t3hIb2h1lDTAx+iYkQlxFuU7QONeyIFIBZ29xvG
# l8pehKxErDzIniOpIX/eluUAwQKoaI0zwuKAdR0mrSHXCniMoLNko5W+5r7sXNam
# KX7QMV3BfGOX3gi9qVfxyUe7AHXbqQ8KBQHNYCnNFtQQHgARrlYhtyAKol5ctM0C
# Ac/y3oY7bTMsVJvnA5u7DVWPeXoST2KEMDeLBvJYq0IJZ6yMpDOWLZ4UP82bksyS
# hIB/XdawirIGLdseudryRxVMk313mAcjGRb59+Ittt6otVvYQWqH+PGrTUzEcez8
# aQuO3umoNZjKuFoX5VsPP/gSZse+orhG3zfZk9IDyE3DfUFrhvkv6H0tijK1D0uI
# GhwMBWSm9ktQ6oeU+aurZFx3MI+LODnHsbRFZAy11uMvwKq+ZNC1Se4tIM1u9piW
# AhnTPoh6mULKikHOVhHaO953tkzDCtjsse5GUKOx9yg9nqHKWMgnODp62/uPPzC/
# yDEISrXCcU7UB7tATr3zWNEdtM4d009iXWI6dV/SdcIIX44rpoLyCLw+nXjxp+fY
# /dygLO7UdSQaVaUFVj3K2nVyuujPspt5Lunc5FvuYPqmi/z8kASmmwbiF+W0P0UT
# WFaC84MWfU2h6MDg5s0oxmdNFK76jXr3wZfdSoV7FCKfq5GdeGoy5UwDQwMC0DGC
# A9QwggPQAgEBMHgwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABa9g1njIXt3QgAAAAAAFowDQYJYIZIAWUDBAIB
# BQCgggEtMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgdwh8qTnwXs3GAX0uJNAzgfD9swWRpWag+FT/VOgH/Hcwgd0GCyqGSIb3DQEJ
# EAIvMYHNMIHKMIHHMIGgBCBiuWRAi+p96PRsBt3TwW3jNozgPQS+Qco1CVm/NaU0
# QzB8MGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBp
# bmcgQ0EgMjAyMAITMwAAAFr2DWeMhe3dCAAAAAAAWjAiBCB0TBVDitlZKQn/2FxQ
# 5fyik0fMbAv4KtpSS+Hb/8Gd0jANBgkqhkiG9w0BAQsFAASCAgARTAGcLCNqkWPw
# MBt69H6ceAFjVIl6ypPzwRrOUTTGg0JcmpjWxTfffuh4HKNnVIckvQox02sq1Zjj
# BcfleUh03d+DPLa3K5X1+Y11aB4fNn3I3u+1sPLTEg7JRRCbF5uL1g6U2qJBi/48
# NBSxrn3qbimM0dQlbCSkIJupRxktKjY6FzmKJ+CAI1ZMgB9yt4Ig4RvVK24V/lgJ
# 21OpK2TC8epHGDxgg6HBvqSkSRI3tKxK9eFAs3ILK56RV3nhGcKH8wJR0lxh7+j8
# KQgV5WkdtK8k/jIM9LiQHZ5Kc4bmG/u6vFSepC4pYSntwEdDWj7czEoTfcjX3mnJ
# XIszGTc1rnvjw36rFAqJm9pPGBuvgB/3qZvu2JC6sWQLPwRt86Zq5vH+skaj5wtD
# uUPES4HZmGVA3iA8K0MDuwnoFQK63CvpdyYSPaJQiNfj/NFK8TwZ3nu5D7UK0XEZ
# CGpqiNNmxPj4/dmXWzoBhy6RELAOxspXes64ppJ2v5WedS5bo0xerzriZ2tW4O+C
# 5M+Fe+VDgKnBbA9XxRcbhy/V+mCXW45GT3VWnbVmgKfc9TPc+8SDVT5ll9cJdIht
# Ed/B4Nle4QDKLxbpTDB4zR0S0UIDpBJs3LP9ZLFeISzcYYDr9n6aIdKflct5a60u
# ilqkzRP+E97xYZCqooT1CpW855MJ1g==
# SIG # End signature block

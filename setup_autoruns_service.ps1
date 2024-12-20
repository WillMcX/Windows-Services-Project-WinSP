[void](Add-Type -AssemblyName System.Windows.Forms | Out-Null)
[void](Add-Type -AssemblyName System.Drawing | Out-Null)

[void](Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32 {
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    }
"@ | Out-Null)

$consoleWindow = (Get-Process -Id $PID).MainWindowHandle
[void][Win32]::ShowWindowAsync($consoleWindow, 0)


$desktopPath = "C:\WinSP\"
$apiKeyPath = "C:\WinSP\apikey.txt"
$nssmDownloadUrl = "https://nssm.cc/release/nssm-2.24.zip"
$downloadFolderNSSM = "C:\nssm"
$autorunsDownloadUrl = "https://download.sysinternals.com/files/Autoruns.zip"
$autorunsFolder = "C:\SysinternalsSuite"
$autorunsZipPath = "$autorunsFolder\Autoruns.zip"
$autorunsPath = "$autorunsFolder\autorunsc.exe"
$pwshDownloadUrl = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.0-win-x64.msi"
$pwshInstallerPath = "C:\Temp\PowerShell7.msi"
$pwshExePath = "C:\Program Files\PowerShell\7\pwsh.exe"
$serviceName = "WinSPv12.3"
$logFilePath = "C:\WinSP\winsp_service_log.txt"
$iconUrl = "https://raw.githubusercontent.com/WillMcX/Windows-Services-Project-WinSP/refs/heads/main/WinSP_logo.ico"
$whitelistFilePath = "C:\WinSP\whitelist.csv"
$authenticodeCsvPath = "C:\WinSP\systemauthenticodes.csv"
$settingsPath = "C:\WinSP\settings.json"
$positivesFilePath = "C:\WinSP\positives.txt"
$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) {
    [System.Windows.Forms.MessageBox]::Show("Error: Script path is not available. Make sure to run this script from a file.", "Error")
    exit 1
}

function Install-PowerShell7 {
    Write-Host "Installing PowerShell 7..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget is not available. Please install PowerShell 7 manually."
        return
    }

    try {
        Start-Process -FilePath "winget" -ArgumentList "install --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements" -NoNewWindow -Wait
        if (Test-Path $pwshExePath) {
            Write-Host "PowerShell 7 installed successfully."
            return $true
        } else {
            Write-Host "PowerShell 7 installation failed."
            return $false
        }
    } catch {
        Write-Host "Error installing PowerShell 7: $($_.Exception.Message)"
        return $false
    }
}

function Stop-OtherInstances {
    $currentPid = $PID
    $currentScriptPath = $MyInvocation.MyCommand.Path
    if (-not $currentScriptPath) {
        Write-Host "Cannot determine the script path. Skipping instance termination."
        return
    }

    Get-Process -Name "pwsh", "powershell" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $processId = $_.Id
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $processId").CommandLine
            if ($cmdLine -match [regex]::Escape($currentScriptPath) -and $processId -ne $currentPid) {
                Write-Host "Stopping another instance of the script with PID $processId"
                Stop-Process -Id $processId -Force
            }
        } catch {
            Write-Host "Failed to retrieve process details for PID $($_.Id): $($_.Exception.Message)"
        }
    }
}

if (-not $env:RUNNING_IN_PWSH7) {
    if ($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.Major -lt 7) {
        if (-not (Test-Path $pwshExePath)) {
            if (-not (Install-PowerShell7)) {
                Write-Host "PowerShell 7 installation failed or not available. Exiting."
                exit 1
            }
        }

        Write-Host "Switching to PowerShell 7..."
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            Write-Host "Error: Script path is not available. Cannot relaunch."
            exit 1
        }

        $env:RUNNING_IN_PWSH7 = "true"
        Start-Process -FilePath $pwshExePath -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-File `"$scriptPath`""
        exit
    }
}


#Stop-OtherInstances

function Ensure-LogFile {
    $logDirectory = [System.IO.Path]::GetDirectoryName($logFilePath)

    if (-not (Test-Path $logDirectory)) {
        New-Item -Path $logDirectory -ItemType Directory | Out-Null
    }

    if (-not (Test-Path $logFilePath)) {
        New-Item -Path $logFilePath -ItemType File | Out-Null
    }
}
Ensure-LogFile
Write-Host "Script is running in PowerShell 7. Continuing..."


function Write-Log {
    param (
        [string]$Message,
        [ref]$TextBox = $null
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedMessage = "$timestamp - $Message"

    if ($TextBox -ne $null -and $TextBox.Value) {
        try {
            $TextBox.Value.AppendText("$formattedMessage`r`n")
        } catch {
            Write-Host "Failed to update GUI log box: $($_.Exception.Message)"
        }
    }
}


function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    exit
}

# Functions to handle service actions/installs
function Install-NSSM {
    Write-Log "NSSM not found. Downloading NSSM..." ([ref]$logBox)
    if (-not (Test-Path $downloadFolderNSSM)) {
        New-Item -Path $downloadFolderNSSM -ItemType Directory
    }
    $zipPath = "$downloadFolderNSSM\nssm.zip"
    Invoke-WebRequest -Uri $nssmDownloadUrl -OutFile $zipPath
    Write-Log "NSSM downloaded. Extracting..." ([ref]$logBox)
    Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $downloadFolderNSSM)
    Write-Log "NSSM extracted successfully." ([ref]$logBox)
}

function Install-Autoruns {
    Write-Log "Autoruns not found. Downloading Autoruns..." ([ref]$logBox)
    if (-not (Test-Path $autorunsFolder)) {
        New-Item -Path $autorunsFolder -ItemType Directory
    }
    Invoke-WebRequest -Uri $autorunsDownloadUrl -OutFile $autorunsZipPath
    Write-Log "Autoruns downloaded. Extracting..." ([ref]$logBox)
    Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($autorunsZipPath, $autorunsFolder)
    Write-Log "Autoruns extracted successfully." ([ref]$logBox)
}

function Install-Service {
    $nssmPath = "$downloadFolderNSSM\nssm-2.24\win64\nssm.exe"
    if (-not (Test-Path $nssmPath)) {
        Install-NSSM
    } else {
        Write-Log "NSSM is already installed. Path: $nssmPath" ([ref]$logBox)
    }

    if (-not (Test-Path $autorunsPath)) {
        Install-Autoruns
    } else {
        Write-Log "Autoruns is already installed. Path: $autorunsPath" ([ref]$logBox)
    }

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Log "Installing NSSM service..." ([ref]$logBox)
        & $nssmPath install $serviceName powershell.exe "-ExecutionPolicy Bypass -File `"$desktopPath\\autoruns_logger.ps1`"" -NoNewWindow -RedirectStandardOutput $logFilePath -RedirectStandardError $logFilePath
        & $nssmPath set $serviceName Start SERVICE_AUTO_START
        Start-Service -Name $serviceName
        Write-Log "Service '$serviceName' installed and started successfully." ([ref]$logBox)
    } else {
        Write-Log "Service '$serviceName' already exists. No action taken." ([ref]$logBox)
    }
}

function Restart-ServiceAction {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq 'Running') {
            Restart-Service -Name $serviceName
            Write-Log "Service restarted successfully." ([ref]$logBox)
        } else {
            Write-Log "Service is not running, attempting to start it..." ([ref]$logBox)
            Start-Service -Name $serviceName
            Write-Log "Service started." ([ref]$logBox)
        }
    } else {
        Write-Log "Service '$serviceName' does not exist. Please install it first." ([ref]$logBox)
    }
}

function Stop-ServiceAction {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $serviceName
            Write-Log "Service stopped successfully." ([ref]$logBox)
        } else {
            Write-Log "Service is already stopped." ([ref]$logBox)
        }
    } else {
        Write-Log "Service '$serviceName' does not exist." ([ref]$logBox)
    }
}

function Uninstall-ServiceAction {
    $nssmPath = "$downloadFolderNSSM\nssm-2.24\win64\nssm.exe"
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "Uninstalling service '$serviceName'..." ([ref]$logBox)
        Stop-Service -Name $serviceName -Force
        & $nssmPath remove $serviceName confirm
        Write-Log "Service '$serviceName' uninstalled successfully." ([ref]$logBox)
    } else {
        Write-Log "Service '$serviceName' does not exist." ([ref]$logBox)
    }
}

function Edit-ApiKey {
    $apiForm = New-Object system.Windows.Forms.Form
    $apiForm.Text = "Edit API Key"
    $apiForm.Size = New-Object System.Drawing.Size(400,200)
    $apiForm.StartPosition = "CenterScreen"

    $apiLabel = New-Object system.Windows.Forms.Label
    $apiLabel.Text = "Current API Key:"
    $apiLabel.AutoSize = $true
    $apiLabel.Location = New-Object System.Drawing.Point(10,20)
    $apiForm.Controls.Add($apiLabel)

    $apiKeyDisplay = New-Object system.Windows.Forms.TextBox
    $apiKeyDisplay.Location = New-Object System.Drawing.Point(10,50)
    $apiKeyDisplay.Width = 300
    if (Test-Path $apiKeyPath) {
        $apiKeyDisplay.Text = Get-Content -Path $apiKeyPath
    } else {
        $apiKeyDisplay.Text = "No API Key found"
    }
    $apiForm.Controls.Add($apiKeyDisplay)

    $apiKeyLabel = New-Object system.Windows.Forms.Label
    $apiKeyLabel.Text = "Enter New API Key:"
    $apiKeyLabel.AutoSize = $true
    $apiKeyLabel.Location = New-Object System.Drawing.Point(10,80)
    $apiForm.Controls.Add($apiKeyLabel)

    $apiKeyBox = New-Object system.Windows.Forms.TextBox
    $apiKeyBox.Location = New-Object System.Drawing.Point(10,110)
    $apiKeyBox.Width = 300
    $apiForm.Controls.Add($apiKeyBox)

    $submitApiButton = New-Object system.Windows.Forms.Button
    $submitApiButton.Text = "Submit API Key"
    $submitApiButton.Location = New-Object System.Drawing.Point(10,140)
    $submitApiButton.Add_Click({
        $newApiKey = $apiKeyBox.Text
        if ($newApiKey) {
            Set-Content -Path $apiKeyPath -Value $newApiKey
            Write-Log "API Key updated successfully." ([ref]$logBox)
            $apiForm.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please enter a valid API Key.")
        }
    })
    $apiForm.Controls.Add($submitApiButton)

    $apiForm.Add_Shown({$apiForm.Activate()})
    [void]$apiForm.ShowDialog()
}

function View-Logs {
    Ensure-LogFile  
    $logForm = New-Object system.Windows.Forms.Form
    $logForm.Text = "WinSP Service Log"
    $logForm.Size = New-Object System.Drawing.Size(600, 400)
    $logForm.StartPosition = "CenterScreen"
    $logForm.TopMost = $false

    try {
    $webClient = New-Object System.Net.WebClient
    $iconStream = [System.IO.MemoryStream]::new($webClient.DownloadData($iconUrl))
    $logForm.Icon = [System.Drawing.Icon]::new($iconStream)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to load icon from URL: $iconUrl. Error: $($_.Exception.Message)", "Error")
    }

    $toolStrip = New-Object System.Windows.Forms.ToolStrip
    $toolStrip.Dock = 'Top'
    $logForm.Controls.Add($toolStrip)

    $realTimeButton = New-Object System.Windows.Forms.ToolStripButton
    $realTimeButton.Text = "Real-Time"
    $realTimeButton.Checked = $true 
    $realTimeButton.CheckOnClick = $true
    $toolStrip.Items.Add($realTimeButton)

    $staticButton = New-Object System.Windows.Forms.ToolStripButton
    $staticButton.Text = "Static"
    $staticButton.CheckOnClick = $true
    $toolStrip.Items.Add($staticButton)

    $realTimeButton.Add_CheckedChanged({
        if ($realTimeButton.Checked) {
            $staticButton.Checked = $false
            $timer.Start()
        }
    })

    $staticButton.Add_CheckedChanged({
        if ($staticButton.Checked) {
            $realTimeButton.Checked = $false
            $timer.Stop()
        }
    })

    $contentPanel = New-Object System.Windows.Forms.Panel
    $contentPanel.Dock = "Fill"
    $contentPanel.Padding = New-Object System.Windows.Forms.Padding(0, 25, 0, 0)  
    $logForm.Controls.Add($contentPanel)

    $logTextBox = New-Object System.Windows.Forms.TextBox
    $logTextBox.Multiline = $true
    $logTextBox.ScrollBars = "Vertical"
    $logTextBox.Dock = "Fill"
    $logTextBox.ReadOnly = $true
    $contentPanel.Controls.Add($logTextBox)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000

    $updateLogs = {
        if (Test-Path $logFilePath) {
            $logTextBox.Text = Get-Content -Path $logFilePath -Raw
            if ($realTimeButton.Checked) {
                $logTextBox.SelectionStart = $logTextBox.Text.Length
                $logTextBox.ScrollToCaret()
            }
        } else {
            $logTextBox.Text = "Log file not found."
        }
    }

    $timer.Add_Tick({
        if ($realTimeButton.Checked) {
            $updateLogs.Invoke()
        }
    })

    $timer.Start()

    $logForm.Add_FormClosing({
        $timer.Stop()
        $timer.Dispose()
    })

    $logForm.Add_Shown({
        $updateLogs.Invoke()
        $logForm.Activate()
    })

    [void]$logForm.ShowDialog()
}

function Check-ServiceStatus {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        $status = $service.Status
        [System.Windows.Forms.MessageBox]::Show("Service '$serviceName' is currently: $status")
    } else {
        [System.Windows.Forms.MessageBox]::Show("Service '$serviceName' does not exist.")
    }
}

function Clear-LogsManually {
    if (Test-Path $logFilePath) {
        Clear-Content -Path $logFilePath
        Write-Log "Logs cleared manually by user." ([ref]$logBox)
        [System.Windows.Forms.MessageBox]::Show("Logs cleared successfully.")
    } else {
        Write-Log "Log file not found for manual clearing." ([ref]$logBox)
        [System.Windows.Forms.MessageBox]::Show("Log file not found.")
    }
}


function Show-VTReport {
    $reportPath = "C:\WinSP\WinSPServiceLogs\VirusTotalReport.csv"

    if (Test-Path $reportPath) {
        $reportForm = New-Object System.Windows.Forms.Form
        $reportForm.Text = "VirusTotal Report"
        $reportForm.Size = New-Object System.Drawing.Size(900, 700)
        $reportForm.StartPosition = "CenterScreen"
        $reportForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $reportForm.MaximizeBox = $false

        $dataGridView = New-Object System.Windows.Forms.DataGridView
        $dataGridView.Dock = 'Fill'
        $dataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
        $dataGridView.AllowUserToResizeColumns = $true
        $dataGridView.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
        $dataGridView.ReadOnly = $true
        $dataGridView.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
        $reportForm.Controls.Add($dataGridView)

        $detailsPanel = New-Object System.Windows.Forms.Panel
        $detailsPanel.Dock = 'Bottom'
        $detailsPanel.Height = 0
        $detailsPanel.Visible = $false
        $detailsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $detailsPanel.BackColor = [System.Drawing.Color]::White
        $reportForm.Controls.Add($detailsPanel)

        $scrollableContainer = New-Object System.Windows.Forms.Panel
        $scrollableContainer.Dock = 'Fill'
        $scrollableContainer.AutoScroll = $true
        $scrollableContainer.AutoScrollMinSize = New-Object System.Drawing.Size(800, 200)
        $detailsPanel.Controls.Add($scrollableContainer)

        $jsonLabel = New-Object System.Windows.Forms.Label
        $jsonLabel.AutoSize = $true
        $jsonLabel.Padding = New-Object System.Windows.Forms.Padding(10)
        $scrollableContainer.Controls.Add($jsonLabel)

        $dataGridView.Add_RowHeaderMouseClick({
            param ($sender, $e)

            if ($detailsPanel.Visible -eq $true -and $detailsPanel.Tag -eq $e.RowIndex) {
                $detailsPanel.Visible = $false
                $detailsPanel.Height = 0
            } else {
                $detailsPanel.Visible = $true
                $detailsPanel.Height = 200
                $detailsPanel.Tag = $e.RowIndex

                $selectedRow = $dataGridView.Rows[$e.RowIndex]
                $jsonObject = @{}
                foreach ($column in $selectedRow.DataGridView.Columns) {
                    $columnName = $column.Name
                    $columnValue = $selectedRow.Cells[$columnName].Value
                    $jsonObject[$columnName] = $columnValue
                }
                $jsonLabel.Text = ($jsonObject | ConvertTo-Json -Depth 10 -Compress:$false)

                $jsonLabel.Width = $scrollableContainer.ClientSize.Width - 20
                $jsonLabel.Height = $jsonLabel.PreferredHeight
            }
        })

        try {
            if ((Get-Content -Path $reportPath -ErrorAction SilentlyContinue | Measure-Object -Line).Lines -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("The VirusTotal report file is empty.", "VirusTotal Report")
            } else {
                $csvData = Import-Csv -Path $reportPath -ErrorAction SilentlyContinue

                if ($csvData.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show("The VirusTotal report file is empty or contains no valid data.", "VirusTotal Report")
                } else {
                    $dataTable = New-Object System.Data.DataTable

                    foreach ($column in $csvData[0].PSObject.Properties.Name) {
                        $dataTable.Columns.Add($column) | Out-Null
                    }

                    foreach ($row in $csvData) {
                        $dataTable.Rows.Add($row.PSObject.Properties.Value) | Out-Null
                    }

                    $dataGridView.DataSource = $dataTable

                    foreach ($col in $dataGridView.Columns) {
                        $col.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::DisplayedCells
                    }
                }
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error loading the VirusTotal report: $($_.Exception.Message)", "VirusTotal Report")
        }

        $reportForm.Add_Shown({$reportForm.Activate()})
        [void]$reportForm.ShowDialog()
    } else {
        [System.Windows.Forms.MessageBox]::Show("VirusTotal report not found at: $reportPath", "VirusTotal Report")
    }
}

function Generate-Whitelist-Window {
    param (
        [string]$authenticodeCsvPath,
        [string]$whitelistFilePath
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Generate Whitelist"
    $form.Size = New-Object System.Drawing.Size(600, 400)
    $form.StartPosition = "CenterScreen"

    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Multiline = $true
    $logBox.ScrollBars = "Vertical"
    $logBox.Dock = "Fill"
    $logBox.ReadOnly = $true
    $form.Controls.Add($logBox)

    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = "Start"
    $startButton.Dock = "Bottom"
    $startButton.Width = 100
    $form.Controls.Add($startButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close"
    $closeButton.Dock = "Bottom"
    $closeButton.Width = 100
    $closeButton.Enabled = $false
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    function Log-Progress {
        param ([string]$message)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logBox.AppendText("$timestamp - $message`r`n")
        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.ScrollToCaret()
    }

    $startButton.Add_Click({
        $startButton.Enabled = $false
        Log-Progress "Starting whitelist generation..."

        $logFilePath = "$whitelistFilePath.log"
        if (Test-Path $logFilePath) {
            Clear-Content -Path $logFilePath
        }

        Start-Job -ScriptBlock {
            param ($authenticodeCsvPath, $whitelistFilePath, $logFilePath)

            function Write-Log {
                param ([string]$message)
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                "$timestamp - $message" | Out-File -FilePath $logFilePath -Append
            }

            Write-Log "Whitelist generation started."

            if (-not (Test-Path $authenticodeCsvPath)) {
                Write-Log "Authenticode CSV file not found: $authenticodeCsvPath"
                return
            }

            try {
                $authenticodes = Import-Csv -Path $authenticodeCsvPath
                Write-Log "Authenticode file loaded successfully."
            } catch {
                Write-Log "Error loading authenticode file: $_"
                return
            }

            if (-not (Test-Path $whitelistFilePath)) {
                "Hash,ProgramName,Path,Details" | Out-File -FilePath $whitelistFilePath
            }

            $existingHashes = @{}
            if (Test-Path $whitelistFilePath) {
                $existingHashes = Import-Csv -Path $whitelistFilePath | ForEach-Object { $_.Hash }
            }

            $totalItems = $authenticodes.Count
            $batchSize = 100
            $batches = [math]::Ceiling($totalItems / $batchSize)
            $processedItems = 0
            $newWhitelistEntries = @()

            Write-Log "Processing $totalItems items in $batches batches."

            for ($batch = 0; $batch -lt $batches; $batch++) {
                $startIndex = $batch * $batchSize
                $endIndex = [math]::Min($startIndex + $batchSize, $totalItems) - 1

                Write-Log "Processing batch $($batch + 1) of ${batches}: items $($startIndex + 1) to $($endIndex + 1)."

                $batchEntries = $authenticodes[$startIndex..$endIndex]

                foreach ($row in $batchEntries) {
                    $filePath = $row.FilePath
                    $status = $row.Status

                    if ($status -ne "Valid") {
                        Write-Log "Skipping item: $filePath (Reason: Invalid status: $status)"
                        continue
                    }

                    if (-not (Test-Path $filePath)) {
                        Write-Log "Skipping item: $filePath (Reason: File not found)"
                        continue
                    }

                    try {
                        $md5Hash = Get-FileHash -Path $filePath -Algorithm MD5 | Select-Object -ExpandProperty Hash

                        if ($existingHashes -contains $md5Hash) {
                            continue
                        }

                        $programName = Split-Path -Path $filePath -Leaf

                        $newWhitelistEntries += [PSCustomObject]@{
                            Hash        = $md5Hash
                            ProgramName = $programName
                            Path        = $filePath
                            
                        }
                    } catch {
                        Write-Log "Error processing file: $filePath. $_"
                        continue
                    }

                    $processedItems++
                }

                Write-Log "Batch $($batch + 1) completed. Total processed: $processedItems."
            }

            if ($newWhitelistEntries.Count -gt 0) {
                $newWhitelistEntries | Export-Csv -Path $whitelistFilePath -Append -NoTypeInformation -Force
            }

            Write-Log "Whitelist generation completed. Processed $processedItems of $totalItems items."
        } -ArgumentList $authenticodeCsvPath, $whitelistFilePath, $logFilePath | Wait-Job

        Log-Progress "Whitelist generation completed. Check the log file for details."
        $closeButton.Enabled = $true
    })

    [void]$form.ShowDialog()
}

function Edit-Whitelist {
    $whitelistPath = "C:\WinSP\whitelist.csv"

    if (-not (Test-Path $whitelistPath)) {
        New-Item -Path $whitelistPath -ItemType File -Force
    }

    $editForm = New-Object System.Windows.Forms.Form
    $editForm.Text = "Edit Whitelist"
    $editForm.Size = New-Object System.Drawing.Size(800, 600)
    $editForm.StartPosition = "CenterScreen"
    $editForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $editForm.MaximizeBox = $false

    $dataGridView = New-Object System.Windows.Forms.DataGridView
    $dataGridView.Dock = 'Top'
    $dataGridView.Height = 500
    $dataGridView.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dataGridView.AllowUserToAddRows = $true
    $dataGridView.AllowUserToDeleteRows = $false
    $editForm.Controls.Add($dataGridView)

    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Dock = 'Bottom'
    $buttonPanel.Height = 50
    $buttonPanel.Padding = New-Object System.Windows.Forms.Padding(5)
    $editForm.Controls.Add($buttonPanel)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = "Save"
    $saveButton.Dock = 'Right'
    $saveButton.Width = 100
    $buttonPanel.Controls.Add($saveButton)

    $deleteButton = New-Object System.Windows.Forms.Button
    $deleteButton.Text = "Delete Row"
    $deleteButton.Dock = 'Left'
    $deleteButton.Width = 100
    $deleteButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $buttonPanel.Controls.Add($deleteButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Dock = 'Right'
    $cancelButton.Width = 100
    $cancelButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
    $buttonPanel.Controls.Add($cancelButton)

    $dataTable = New-Object System.Data.DataTable

    try {
        if ((Get-Content -Path $whitelistPath -ErrorAction SilentlyContinue | Measure-Object -Line).Lines -eq 0) {
            #[System.Windows.Forms.MessageBox]::Show("Whitelist is empty. You can add entries.")
            $dataTable.Columns.Add("Hash") | Out-Null
        } else {
            $csvData = Import-Csv -Path $whitelistPath

            if ($csvData.Count -eq 0 -or $csvData[0] -eq $null) {
                $dataTable.Columns.Add("Hash") | Out-Null
            } else {    
                foreach ($column in $csvData[0].PSObject.Properties.Name) {
                    $dataTable.Columns.Add($column) | Out-Null
                }

                foreach ($row in $csvData) {
                    $dataTable.Rows.Add($row.PSObject.Properties.Value) | Out-Null
                }
            }
        }

        $dataGridView.DataSource = $dataTable
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error loading whitelist: $($_.Exception.Message)")
    }

    $saveButton.Add_Click({
        try {
            $dataTable = $dataGridView.DataSource
            $output = @()

            foreach ($row in $dataTable.Rows) {
                if ($row.RowState -ne [System.Data.DataRowState]::Deleted) {
                    $properties = @{}
                    foreach ($col in $dataTable.Columns) {
                        $properties[$col.ColumnName] = $row[$col.ColumnName]
                    }
                    $output += [PSCustomObject]$properties
                }
            }

            $output | Export-Csv -Path $whitelistPath -NoTypeInformation -Force
            [System.Windows.Forms.MessageBox]::Show("Whitelist saved successfully.")
            $editForm.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error saving whitelist: $($_.Exception.Message)")
        }
    })

    $deleteButton.Add_Click({
        try {
            $selectedRowIndex = $dataGridView.SelectedCells[0].RowIndex
            if ($selectedRowIndex -ne $null -and $selectedRowIndex -ge 0) {
                $dataGridView.Rows.RemoveAt($selectedRowIndex)
            } else {
                [System.Windows.Forms.MessageBox]::Show("Please select a valid row to delete.")
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error deleting row: $($_.Exception.Message)")
        }
    })

    $cancelButton.Add_Click({
        $editForm.Close()
    })

    $editForm.Add_Shown({$editForm.Activate()})
    [void]$editForm.ShowDialog()
}

function Open-LogFolder {
    $logFolderPath = "C:\WinSP\WinSPServiceLogs"

    if (-not (Test-Path $logFolderPath)) {
        New-Item -Path $logFolderPath -ItemType Directory -Force
        [System.Windows.Forms.MessageBox]::Show("Log folder does not exist. A new one has been created at: $logFolderPath")
    }

    try {
        Start-Process -FilePath $logFolderPath
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error opening the log folder: $($_.Exception.Message)")
    }
}

function Ensure-SettingsFile {
    if (-not (Test-Path $settingsPath)) {
        $defaultSettings = @{
            Interval = 86400  #1 Day
        }
        $defaultSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Force
        Write-Host "Settings file created with default interval: 86400 seconds (1 day)."
    }
}

Ensure-SettingsFile

function Edit-Settings {
    Ensure-SettingsFile

    $settingsForm = New-Object system.Windows.Forms.Form
    $settingsForm.Text = "Edit Settings"
    $settingsForm.Size = New-Object System.Drawing.Size(300, 200)
    $settingsForm.StartPosition = "CenterScreen"

    $intervalLabel = New-Object system.Windows.Forms.Label
    $intervalLabel.Text = "Set Run Interval (seconds):"
    $intervalLabel.Location = New-Object System.Drawing.Point(10, 20)
    $intervalLabel.AutoSize = $true
    $settingsForm.Controls.Add($intervalLabel)

    $intervalBox = New-Object system.Windows.Forms.TextBox
    $intervalBox.Location = New-Object System.Drawing.Point(10, 50)
    $intervalBox.Width = 100
    $settingsForm.Controls.Add($intervalBox)

    # Load current settings
    $currentSettings = Get-Content -Path $settingsPath | ConvertFrom-Json
    $intervalBox.Text = $currentSettings.Interval

    $saveButton = New-Object system.Windows.Forms.Button
    $saveButton.Text = "Save"
    $saveButton.Location = New-Object System.Drawing.Point(10, 90)
    $saveButton.Add_Click({
        $newInterval = $intervalBox.Text -as [int]
        if ($newInterval -gt 0) {
            $currentSettings.Interval = $newInterval
            $currentSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Force

            # Log the interval change
            $logMessage = "Interval setting updated to $newInterval seconds."
            Write-Log $logMessage ([ref]$logBox)  # Update log text box
            [System.Windows.Forms.MessageBox]::Show("Settings saved successfully.")
            $settingsForm.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please enter a valid positive number for the interval.")
        }
    })
    $settingsForm.Controls.Add($saveButton)

    $settingsForm.Add_Shown({$settingsForm.Activate()})
    [void]$settingsForm.ShowDialog()
}




function Ensure-BurntToastModule {
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        try {
            Install-Module -Name BurntToast -Scope CurrentUser -Force -SkipPublisherCheck
        } catch {
            Write-Host "Failed to install BurntToast module. Please install it manually. Error: $_"
            exit 1
        }
    }
    Import-Module BurntToast -Force
}

# Initialize BurntToast
Ensure-BurntToastModule

function Start-NotifHelper {
    $notifHelperPath = "C:\WinSP\notif_helper.ps1"

    # Check if the process is already running
    $running = Get-Process -Name "pwsh" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $processId = $_.Id
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $processId").CommandLine
            if ($cmdLine -match [regex]::Escape($notifHelperPath)) {
                return $true
            }
        } catch {
            Write-Host "Failed to get command line for process ID $processId. Error: $_"
        }
    }

    if ($running) {
        Write-Host "Notification helper is already running."
        return
    }

    # Start the notif helper as a separate PowerShell process
    try {
        Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-File `"$notifHelperPath`"" -WindowStyle Hidden
        Write-Host "Notification helper started as a background process."
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error: Could not start Notification Helper.", "Error")
    }
}





Start-NotifHelper


#Menu Bar
$menuStrip = New-Object System.Windows.Forms.MenuStrip

$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$fileMenu.Text = "File"
$restartMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$restartMenuItem.Text = "Restart"
$restartMenuItem.Add_Click({
    try {
        if (-not (Test-Path $scriptPath)) {
            [System.Windows.Forms.MessageBox]::Show("Error: Script path could not be determined. Unable to restart.", "Restart Error")
            return
        }

        if (-not (Test-Path $pwshExePath)) {
            [System.Windows.Forms.MessageBox]::Show("PowerShell 7 is not installed. Please install PowerShell 7 first.", "Restart Error")
            return
        }

        # Restart main script
        Start-Process -FilePath $pwshExePath -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-File `"$scriptPath`"" -WindowStyle Normal

        # Ensure Notification Helper starts
        Start-NotifHelper

        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error occurred during restart: $($_.Exception.Message)", "Restart Error")
    }
})

$fileMenu.DropDownItems.Add($restartMenuItem)
$settingsMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$settingsMenuItem.Text = "Settings"
$settingsMenuItem.Add_Click({ Edit-Settings })
$fileMenu.DropDownItems.Add($settingsMenuItem)
$exitMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitMenuItem.Text = "Exit"
$exitMenuItem.Add_Click({ $form.Close() })
$fileMenu.DropDownItems.Add($exitMenuItem)
$menuStrip.Items.Add($fileMenu)

$editMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$editMenu.Text = "Edit"
$editApiKeyMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$editApiKeyMenuItem.Text = "Edit API Key"
$editApiKeyMenuItem.Add_Click({ Edit-ApiKey })
$editWhitelistMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$editWhitelistMenuItem.Text = "Edit Whitelist"
$editWhitelistMenuItem.Add_Click({ Edit-Whitelist })
$genWhitelistMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$genWhitelistMenuItem.Text = "Generate / Update Whitelist"
$genWhitelistMenuItem.Add_Click({
    Generate-Whitelist-Window -authenticodeCsvPath $authenticodeCsvPath -whitelistFilePath $whitelistFilePath
})
$editMenu.DropDownItems.Add($editApiKeyMenuItem)
$editMenu.DropDownItems.Add($editWhitelistMenuItem)
$editMenu.DropDownItems.Add($genWhitelistMenuItem)
$menuStrip.Items.Add($editMenu)


$helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$helpMenu.Text = "Help"
$aboutMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem
$aboutMenuItem.Text = "About"
$aboutMenuItem.Add_Click({
    $aboutText = @"
                                    WinSP Service Manager v10.2
                                      Created By: William McCoy
--------------------------------------------------------------------------------------------

This program is designed to scan Windows services and assist with system monitoring by leveraging Autoruns and VirusTotal API integration.

Features:
1. Service Management:
   - Install, uninstall, stop, restart, and check the status of the WinSP Service.

2. Logging and Reporting:
   - Generate detailed logs of system activities and store them (C:\WinSP).
   - View, clear, and open log files directly from the interface.

3. Threat Assessment:
   - Use Autoruns to monitor system changes and generate JSON reports of new or modified items.
   - Identify changes between successive scans to detect potentially malicious or suspicious activity.

4. VirusTotal Integration:
   - Query VirusTotal's API for hash-based threat assessment of system changes.
   - Retrieve scan results, including detections, scan dates, and detailed scan reports for each hash.

5. Whitelist Management:
   - Maintain a whitelist to ignore known safe hashes during threat assessments.
   - Add, remove, or edit whitelist entries through the interface.

6. Configuration Options:
   - Update and manage the VirusTotal API key securely.
   - Configure application settings.

This tool is ideal for administrators and security analysts who need to monitor and assess system changes, monitor services, and evaluate potential threats efficiently in the background.
                                    This tool is currently a W.I.P!
"@

    [System.Windows.Forms.MessageBox]::Show($aboutText, "About")
})
$helpMenu.DropDownItems.Add($aboutMenuItem)
$menuStrip.Items.Add($helpMenu)



# Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "WinSP Service Manager"
$form.Size = New-Object System.Drawing.Size(825, 625)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.Controls.Add($menuStrip)
$form.MainMenuStrip = $menuStrip
$menuStrip.Dock = "Top"

try {
    $webClient = New-Object System.Net.WebClient
    $iconStream = [System.IO.MemoryStream]::new($webClient.DownloadData($iconUrl))
    $form.Icon = [System.Drawing.Icon]::new($iconStream)
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load icon from URL: $iconUrl. Error: $($_.Exception.Message)", "Error")
}

$imageUrl = "https://raw.githubusercontent.com/WillMcX/Windows-Services-Project-WinSP/refs/heads/main/WinSP_logo.png"
$pictureBox = New-Object System.Windows.Forms.PictureBox
$pictureBox.Location = New-Object System.Drawing.Point(20, 50)
$pictureBox.Size = New-Object System.Drawing.Size(300, 300)
$pictureBox.BorderStyle = 'FixedSingle'
$pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

try {
    $webClient = New-Object System.Net.WebClient
    $imageStream = [System.IO.MemoryStream]::new($webClient.DownloadData($imageUrl))
    $pictureBox.Image = [System.Drawing.Image]::FromStream($imageStream)
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load image from URL: $imageUrl. Error: $($_.Exception.Message)", "Error")
}
$form.Controls.Add($pictureBox)

$serviceLabel = New-Object System.Windows.Forms.Label
$serviceLabel.Text = "Service"
$serviceLabel.Location = New-Object System.Drawing.Point(350, 50)
$serviceLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$serviceLabel.AutoSize = $true
$form.Controls.Add($serviceLabel)

$loggingLabel = New-Object System.Windows.Forms.Label
$loggingLabel.Text = "Logging"
$loggingLabel.Location = New-Object System.Drawing.Point(350, 220)
$loggingLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$loggingLabel.AutoSize = $true
$form.Controls.Add($loggingLabel)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Install Service"
$installButton.Size = New-Object System.Drawing.Size(120, 40)
$installButton.Location = New-Object System.Drawing.Point(350, 80)
$installButton.Add_Click({ Install-Service })
$form.Controls.Add($installButton)

$uninstallButton = New-Object System.Windows.Forms.Button
$uninstallButton.Text = "Uninstall Service"
$uninstallButton.Size = New-Object System.Drawing.Size(120, 40)
$uninstallButton.Location = New-Object System.Drawing.Point(480, 80)
$uninstallButton.Add_Click({ Uninstall-ServiceAction })
$form.Controls.Add($uninstallButton)

$restartButton = New-Object System.Windows.Forms.Button
$restartButton.Text = "Restart Service"
$restartButton.Size = New-Object System.Drawing.Size(120, 40)
$restartButton.Location = New-Object System.Drawing.Point(610, 80)
$restartButton.Add_Click({ Restart-ServiceAction })
$form.Controls.Add($restartButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop Service"
$stopButton.Size = New-Object System.Drawing.Size(120, 40)
$stopButton.Location = New-Object System.Drawing.Point(350, 130)
$stopButton.Add_Click({ Stop-ServiceAction })
$form.Controls.Add($stopButton)

$statusButton = New-Object System.Windows.Forms.Button
$statusButton.Text = "Service Status"
$statusButton.Size = New-Object System.Drawing.Size(120, 40)
$statusButton.Location = New-Object System.Drawing.Point(480, 130)
$statusButton.Add_Click({ Check-ServiceStatus })
$form.Controls.Add($statusButton)

$viewLogsButton = New-Object System.Windows.Forms.Button
$viewLogsButton.Text = "View Logs"
$viewLogsButton.Size = New-Object System.Drawing.Size(120, 40)
$viewLogsButton.Location = New-Object System.Drawing.Point(350, 250)
$viewLogsButton.Add_Click({ View-Logs })
$form.Controls.Add($viewLogsButton)

$openLogFolderButton = New-Object System.Windows.Forms.Button
$openLogFolderButton.Text = "Open Log Folder"
$openLogFolderButton.Size = New-Object System.Drawing.Size(120, 40)
$openLogFolderButton.Location = New-Object System.Drawing.Point(480, 250)
$openLogFolderButton.Add_Click({ Open-LogFolder })
$form.Controls.Add($openLogFolderButton)

$clearLogsButton = New-Object System.Windows.Forms.Button
$clearLogsButton.Text = "Clear Logs"
$clearLogsButton.Size = New-Object System.Drawing.Size(120, 40)
$clearLogsButton.Location = New-Object System.Drawing.Point(610, 250)
$clearLogsButton.Add_Click({ Clear-LogsManually })
$form.Controls.Add($clearLogsButton)

$vtReportButton = New-Object System.Windows.Forms.Button
$vtReportButton.Text = "Show VT Report"
$vtReportButton.Size = New-Object System.Drawing.Size(120, 40)
$vtReportButton.Location = New-Object System.Drawing.Point(350, 300)
$vtReportButton.Add_Click({ Show-VTReport })
$form.Controls.Add($vtReportButton)

$authenticodeButton = New-Object System.Windows.Forms.Button
$authenticodeButton.Text = "Authenticode Update"
$authenticodeButton.Size = New-Object System.Drawing.Size(120, 40)
$authenticodeButton.Location = New-Object System.Drawing.Point(610, 130)
$authenticodeButton.Add_Click({
    try {
        # Path to PowerShell 7 executable
        $pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

        # Path to the Authenticode script
        $scriptPath = "C:\WinSP\AuthenticodeUpdate.ps1"

        # Ensure PowerShell 7 is installed
        if (-not (Test-Path $pwshPath)) {
            [System.Windows.Forms.MessageBox]::Show("PowerShell 7 is not installed. Please install it first.", "Error")
            return
        }

        # Ensure the script exists
        if (-not (Test-Path $scriptPath)) {
            [System.Windows.Forms.MessageBox]::Show("The Authenticode Update script does not exist at $scriptPath.", "Error")
            return
        }

        # Start a new PowerShell process to execute the script
        Start-Process -FilePath $pwshPath -ArgumentList "-NoExit", "-File", "`"$scriptPath`"" -WindowStyle Normal
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error launching Authenticode Update: $($_.Exception.Message)", "Error")
    }
})
$form.Controls.Add($authenticodeButton)


$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.Location = New-Object System.Drawing.Point(20, 370)
$logBox.Size = New-Object System.Drawing.Size(760, 200)
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

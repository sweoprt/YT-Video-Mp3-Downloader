Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BinDir = Join-Path $script:AppRoot "bin"
$script:TempDir = Join-Path $script:AppRoot "tmp"
$script:DenoCacheDir = Join-Path $script:BinDir "deno-cache"
$script:YtDlpPath = Join-Path $script:BinDir "yt-dlp.exe"
$script:DenoPath = Join-Path $script:BinDir "deno.exe"
$script:FfmpegPath = Join-Path $script:BinDir "ffmpeg.exe"
$script:DefaultOutputDir = [Environment]::GetFolderPath("MyVideos")

if ([string]::IsNullOrWhiteSpace($script:DefaultOutputDir) -or -not (Test-Path $script:DefaultOutputDir)) {
    $script:DefaultOutputDir = [Environment]::GetFolderPath("Desktop")
}

$script:ResolutionChoices = [System.Collections.ArrayList]@("Best", "2160p", "1440p", "1080p", "720p", "480p", "360p", "240p", "144p")

function Write-Log {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    $script:LogBox.AppendText("$Message`r`n")
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Status {
    param([string]$Message)

    $script:StatusLabel.Text = "Status: $Message"
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-BusyState {
    param([bool]$IsBusy)

    $script:LoadButton.Enabled = -not $IsBusy
    $script:DownloadButton.Enabled = -not $IsBusy
    $script:BrowseButton.Enabled = -not $IsBusy
    $script:ClearButton.Enabled = -not $IsBusy
    $script:FormatBox.Enabled = -not $IsBusy
    $script:UrlBox.Enabled = -not $IsBusy
    $script:OutputBox.Enabled = -not $IsBusy

    if ($script:FormatBox.SelectedItem -eq "MP3") {
        $script:ResolutionBox.Enabled = $false
    } else {
        $script:ResolutionBox.Enabled = -not $IsBusy
    }

    [System.Windows.Forms.Application]::DoEvents()
}

function Get-YtDlpUrl {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        return "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_arm64.exe"
    }

    return "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
}

function Get-DenoUrl {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        return "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-pc-windows-msvc.zip"
    }

    return "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip"
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination
    )

    $parentDir = Split-Path -Parent $Destination
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Write-Log "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Install-YtDlp {
    if (Test-Path $script:YtDlpPath) {
        return
    }

    New-Item -ItemType Directory -Path $script:BinDir -Force | Out-Null
    Download-File -Url (Get-YtDlpUrl) -Destination $script:YtDlpPath
    Write-Log "yt-dlp is ready."
}

function Install-Deno {
    if (Test-Path $script:DenoPath) {
        return
    }

    $zipPath = Join-Path $script:TempDir "deno.zip"
    $extractDir = Join-Path $script:TempDir "deno"

    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    Download-File -Url (Get-DenoUrl) -Destination $zipPath

    if (Test-Path $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }

    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $denoExe = Get-ChildItem -Path $extractDir -Recurse -Filter "deno.exe" | Select-Object -First 1
    if (-not $denoExe) {
        throw "Could not find deno.exe in the downloaded archive."
    }

    Copy-Item -LiteralPath $denoExe.FullName -Destination $script:DenoPath -Force
    Write-Log "Deno runtime is ready."
}

function Install-Ffmpeg {
    if (Test-Path $script:FfmpegPath) {
        return
    }

    $zipPath = Join-Path $script:TempDir "ffmpeg.zip"
    $extractDir = Join-Path $script:TempDir "ffmpeg"

    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    Download-File -Url "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -Destination $zipPath

    if (Test-Path $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }

    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $ffmpegExe = Get-ChildItem -Path $extractDir -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
    $ffprobeExe = Get-ChildItem -Path $extractDir -Recurse -Filter "ffprobe.exe" | Select-Object -First 1

    if (-not $ffmpegExe) {
        throw "Could not find ffmpeg.exe in the downloaded archive."
    }

    Copy-Item -LiteralPath $ffmpegExe.FullName -Destination $script:FfmpegPath -Force

    if ($ffprobeExe) {
        Copy-Item -LiteralPath $ffprobeExe.FullName -Destination (Join-Path $script:BinDir "ffprobe.exe") -Force
    }

    Write-Log "FFmpeg is ready."
}

function Ensure-PortableTools {
    if (-not (Test-Path $script:BinDir)) {
        New-Item -ItemType Directory -Path $script:BinDir -Force | Out-Null
    }

    if (-not (Test-Path $script:DenoCacheDir)) {
        New-Item -ItemType Directory -Path $script:DenoCacheDir -Force | Out-Null
    }

    Install-YtDlp
    Install-Deno
    Install-Ffmpeg
}

function Invoke-YtDlpCapture {
    param([string[]]$Arguments)

    $oldDenoDir = $env:DENO_DIR
    $env:DENO_DIR = $script:DenoCacheDir

    try {
        $output = & $script:YtDlpPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        return [PSCustomObject]@{
            Output = @($output | ForEach-Object { $_.ToString() })
            ExitCode = $exitCode
        }
    }
    finally {
        if ($null -eq $oldDenoDir) {
            Remove-Item Env:\DENO_DIR -ErrorAction SilentlyContinue
        } else {
            $env:DENO_DIR = $oldDenoDir
        }
    }
}

function Invoke-YtDlpStreaming {
    param([string[]]$Arguments)

    $oldDenoDir = $env:DENO_DIR
    $env:DENO_DIR = $script:DenoCacheDir

    try {
        & $script:YtDlpPath @Arguments 2>&1 | ForEach-Object {
            $line = $_.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Write-Log $line
                if ($line.Contains("[download]")) {
                    Set-Status $line
                }
            }
        }
        return $LASTEXITCODE
    }
    finally {
        if ($null -eq $oldDenoDir) {
            Remove-Item Env:\DENO_DIR -ErrorAction SilentlyContinue
        } else {
            $env:DENO_DIR = $oldDenoDir
        }
    }
}

function Get-AvailableResolutions {
    param([string]$Url)

    $args = @(
        "--dump-single-json",
        "--no-playlist",
        "--no-warnings",
        "--skip-download",
        "--ffmpeg-location", $script:BinDir,
        "--js-runtimes", "deno:$script:DenoPath",
        $Url
    )

    $result = Invoke-YtDlpCapture -Arguments $args
    if ($result.ExitCode -ne 0) {
        throw (($result.Output -join "`n").Trim())
    }

    $jsonText = ($result.Output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw "yt-dlp did not return video metadata."
    }

    $info = $jsonText | ConvertFrom-Json -Depth 100
    $heights = New-Object System.Collections.Generic.HashSet[int]

    foreach ($format in $info.formats) {
        if ($format.vcodec -eq "none") {
            continue
        }

        if ($null -ne $format.height) {
            $heightValue = 0
            if ([int]::TryParse($format.height.ToString(), [ref]$heightValue) -and $heightValue -gt 0) {
                [void]$heights.Add($heightValue)
            }
        }
    }

    $choices = New-Object System.Collections.ArrayList
    [void]$choices.Add("Best")

    foreach ($height in ($heights | Sort-Object -Descending)) {
        [void]$choices.Add("${height}p")
    }

    if ($choices.Count -eq 1) {
        foreach ($fallback in @("2160p", "1440p", "1080p", "720p", "480p", "360p", "240p", "144p")) {
            [void]$choices.Add($fallback)
        }
    }

    return $choices
}

function Update-ResolutionChoices {
    param([System.Collections.IEnumerable]$Choices)

    $script:ResolutionBox.Items.Clear()
    foreach ($choice in $Choices) {
        [void]$script:ResolutionBox.Items.Add($choice)
    }
    $script:ResolutionBox.SelectedItem = "Best"
}

function Build-DownloadArguments {
    param(
        [string]$Url,
        [string]$OutputDir,
        [string]$TargetFormat,
        [string]$Resolution
    )

    $outputTemplate = Join-Path $OutputDir "%(title)s.%(ext)s"
    $arguments = @(
        "--newline",
        "--no-playlist",
        "--windows-filenames",
        "--ffmpeg-location", $script:BinDir,
        "--js-runtimes", "deno:$script:DenoPath",
        "-o", $outputTemplate
    )

    if ($TargetFormat -eq "MP3") {
        $arguments += @("-x", "--audio-format", "mp3", "--audio-quality", "0")
    } else {
        if ($Resolution -eq "Best") {
            $formatSelector = "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/best"
        } else {
            $height = $Resolution.Replace("p", "")
            $formatSelector = "bv*[ext=mp4][height<=$height]+ba[ext=m4a]/b[ext=mp4][height<=$height]/best[height<=$height]"
        }

        $arguments += @("-f", $formatSelector, "--merge-output-format", "mp4")
    }

    $arguments += $Url
    return $arguments
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Portable YouTube Downloader"
$form.Size = New-Object System.Drawing.Size(820, 640)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(820, 640)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 251)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Portable YouTube Downloader"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(20, 16)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "No Python or manual setup needed. The app downloads its own tools into this folder the first time you use it."
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitle.Location = New-Object System.Drawing.Point(22, 52)
$subtitle.Size = New-Object System.Drawing.Size(760, 32)
$form.Controls.Add($subtitle)

$urlLabel = New-Object System.Windows.Forms.Label
$urlLabel.Text = "Video URL"
$urlLabel.Location = New-Object System.Drawing.Point(22, 96)
$urlLabel.AutoSize = $true
$form.Controls.Add($urlLabel)

$script:UrlBox = New-Object System.Windows.Forms.TextBox
$script:UrlBox.Location = New-Object System.Drawing.Point(22, 118)
$script:UrlBox.Size = New-Object System.Drawing.Size(760, 27)
$script:UrlBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($script:UrlBox)

$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Save To"
$outputLabel.Location = New-Object System.Drawing.Point(22, 160)
$outputLabel.AutoSize = $true
$form.Controls.Add($outputLabel)

$script:OutputBox = New-Object System.Windows.Forms.TextBox
$script:OutputBox.Location = New-Object System.Drawing.Point(22, 182)
$script:OutputBox.Size = New-Object System.Drawing.Size(620, 27)
$script:OutputBox.Text = $script:DefaultOutputDir
$script:OutputBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($script:OutputBox)

$script:BrowseButton = New-Object System.Windows.Forms.Button
$script:BrowseButton.Text = "Browse"
$script:BrowseButton.Location = New-Object System.Drawing.Point(652, 180)
$script:BrowseButton.Size = New-Object System.Drawing.Size(130, 31)
$form.Controls.Add($script:BrowseButton)

$formatLabel = New-Object System.Windows.Forms.Label
$formatLabel.Text = "Format"
$formatLabel.Location = New-Object System.Drawing.Point(22, 228)
$formatLabel.AutoSize = $true
$form.Controls.Add($formatLabel)

$script:FormatBox = New-Object System.Windows.Forms.ComboBox
$script:FormatBox.Location = New-Object System.Drawing.Point(22, 250)
$script:FormatBox.Size = New-Object System.Drawing.Size(180, 28)
$script:FormatBox.DropDownStyle = "DropDownList"
[void]$script:FormatBox.Items.Add("MP4")
[void]$script:FormatBox.Items.Add("MP3")
$script:FormatBox.SelectedItem = "MP4"
$form.Controls.Add($script:FormatBox)

$resolutionLabel = New-Object System.Windows.Forms.Label
$resolutionLabel.Text = "Resolution"
$resolutionLabel.Location = New-Object System.Drawing.Point(220, 228)
$resolutionLabel.AutoSize = $true
$form.Controls.Add($resolutionLabel)

$script:ResolutionBox = New-Object System.Windows.Forms.ComboBox
$script:ResolutionBox.Location = New-Object System.Drawing.Point(220, 250)
$script:ResolutionBox.Size = New-Object System.Drawing.Size(180, 28)
$script:ResolutionBox.DropDownStyle = "DropDownList"
$form.Controls.Add($script:ResolutionBox)
Update-ResolutionChoices -Choices $script:ResolutionChoices

$script:LoadButton = New-Object System.Windows.Forms.Button
$script:LoadButton.Text = "Load Resolutions"
$script:LoadButton.Location = New-Object System.Drawing.Point(420, 248)
$script:LoadButton.Size = New-Object System.Drawing.Size(170, 32)
$form.Controls.Add($script:LoadButton)

$script:DownloadButton = New-Object System.Windows.Forms.Button
$script:DownloadButton.Text = "Download"
$script:DownloadButton.Location = New-Object System.Drawing.Point(602, 248)
$script:DownloadButton.Size = New-Object System.Drawing.Size(180, 32)
$script:DownloadButton.BackColor = [System.Drawing.Color]::FromArgb(33, 115, 70)
$script:DownloadButton.ForeColor = [System.Drawing.Color]::White
$script:DownloadButton.FlatStyle = "Flat"
$form.Controls.Add($script:DownloadButton)

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = "Status: Ready"
$script:StatusLabel.Location = New-Object System.Drawing.Point(22, 296)
$script:StatusLabel.Size = New-Object System.Drawing.Size(760, 20)
$script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(30, 110, 65)
$form.Controls.Add($script:StatusLabel)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = "Progress / Log"
$logLabel.Location = New-Object System.Drawing.Point(22, 328)
$logLabel.AutoSize = $true
$form.Controls.Add($logLabel)

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Location = New-Object System.Drawing.Point(22, 350)
$script:LogBox.Size = New-Object System.Drawing.Size(760, 212)
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($script:LogBox)

$script:ClearButton = New-Object System.Windows.Forms.Button
$script:ClearButton.Text = "Clear Log"
$script:ClearButton.Location = New-Object System.Drawing.Point(652, 572)
$script:ClearButton.Size = New-Object System.Drawing.Size(130, 30)
$form.Controls.Add($script:ClearButton)

Write-Log "Portable app ready."

$script:BrowseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $script:OutputBox.Text
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:OutputBox.Text = $dialog.SelectedPath
    }
})

$script:ClearButton.Add_Click({
    $script:LogBox.Clear()
    Write-Log "Log cleared."
})

$script:FormatBox.Add_SelectedIndexChanged({
    if ($script:FormatBox.SelectedItem -eq "MP3") {
        $script:ResolutionBox.SelectedItem = "Best"
        $script:ResolutionBox.Enabled = $false
    } else {
        $script:ResolutionBox.Enabled = $true
    }
})

$script:LoadButton.Add_Click({
    $url = $script:UrlBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($url)) {
        [System.Windows.Forms.MessageBox]::Show("Paste a YouTube link first.", "Missing URL")
        return
    }

    try {
        Set-BusyState -IsBusy $true
        Set-Status "Preparing local tools..."
        Ensure-PortableTools
        Set-Status "Fetching resolutions..."
        Write-Log "Checking available resolutions for: $url"
        $choices = Get-AvailableResolutions -Url $url
        Update-ResolutionChoices -Choices $choices
        Set-Status "Resolution list loaded"
        Write-Log "Resolution list updated."
    }
    catch {
        Set-Status "Could not load resolutions"
        Write-Log $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Failed")
    }
    finally {
        Set-BusyState -IsBusy $false
    }
})

$script:DownloadButton.Add_Click({
    $url = $script:UrlBox.Text.Trim()
    $outputDir = $script:OutputBox.Text.Trim()
    $targetFormat = [string]$script:FormatBox.SelectedItem
    $resolution = [string]$script:ResolutionBox.SelectedItem

    if ([string]::IsNullOrWhiteSpace($url)) {
        [System.Windows.Forms.MessageBox]::Show("Paste a YouTube link first.", "Missing URL")
        return
    }

    if ([string]::IsNullOrWhiteSpace($outputDir)) {
        [System.Windows.Forms.MessageBox]::Show("Choose a save folder first.", "Missing Folder")
        return
    }

    if (-not (Test-Path $outputDir)) {
        [System.Windows.Forms.MessageBox]::Show("The selected save folder does not exist.", "Missing Folder")
        return
    }

    if ([string]::IsNullOrWhiteSpace($resolution)) {
        $resolution = "Best"
    }

    try {
        Set-BusyState -IsBusy $true
        Set-Status "Preparing local tools..."
        Ensure-PortableTools
        Write-Log "Starting download: $url"
        Write-Log "Format: $targetFormat | Resolution: $resolution"
        Set-Status "Downloading..."

        $args = Build-DownloadArguments -Url $url -OutputDir $outputDir -TargetFormat $targetFormat -Resolution $resolution
        $exitCode = Invoke-YtDlpStreaming -Arguments $args

        if ($exitCode -eq 0) {
            Set-Status "Download finished"
            Write-Log "Download completed successfully."
            [System.Windows.Forms.MessageBox]::Show("The download finished successfully.", "Done")
        } else {
            Set-Status "Download failed"
            Write-Log "Download failed with exit code $exitCode."
            [System.Windows.Forms.MessageBox]::Show("Download failed. Check the log for details.", "Failed")
        }
    }
    catch {
        Set-Status "Download failed"
        Write-Log $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Failed")
    }
    finally {
        Set-BusyState -IsBusy $false
    }
})

[void]$form.ShowDialog()

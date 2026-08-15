Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Base = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:Adb = Join-Path $script:Base "platform-tools\adb.exe"
$script:Serial = $null
$script:CancelRequested = $false
$script:Sources = @(
    "/sdcard/DCIM", "/sdcard/Pictures", "/sdcard/Movies",
    "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images",
    "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video"
)
$script:Extensions = @(".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif", ".dng", ".mp4", ".mov", ".m4v", ".3gp", ".mkv", ".avi", ".webm")

function Invoke-Adb([string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $script:Adb @Arguments 2>&1
        $code = $LASTEXITCODE
        return @{ Code = $code; Output = ($output -join "`n") }
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Read-SharedText([string]$Path) {
    # Permite ler o estado mesmo durante uma atualização feita pelo processo
    # de backup. Se o JSON estiver pela metade, o timer tenta novamente.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-StateFiles {
    $directory = Split-Path -Parent $script:ProgressFile
    $prefix = (Split-Path -Leaf $script:ProgressFile) + ".*.state"
    return @(Get-ChildItem -LiteralPath $directory -Filter $prefix -File -ErrorAction SilentlyContinue)
}

function Clear-StateFiles {
    Get-StateFiles | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Get-RecordedDate([string]$Path, [string]$Name) {
    if ([IO.Path]::GetExtension($Path) -match '^\.(jpg|jpeg)$') {
        try {
            $image = [Drawing.Image]::FromFile($Path)
            try {
                $prop = $image.GetPropertyItem(36867)
                $text = [Text.Encoding]::ASCII.GetString($prop.Value).Trim([char]0)
                $parsed = [datetime]::MinValue
                if ([datetime]::TryParseExact($text, "yyyy:MM:dd HH:mm:ss", $null, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { return @{ Date=$parsed; Source="metadata" } }
            } finally { $image.Dispose() }
        } catch { }
    }
    $match = [regex]::Match($Name, '(?<!\d)((?:19|20)\d{2})[-_]?([01]\d)[-_]?([0-3]\d)(?!\d)')
    if ($match.Success) {
        try {
            $date = [datetime]::new([int]$match.Groups[1].Value, [int]$match.Groups[2].Value, [int]$match.Groups[3].Value)
            if ($date.Year -le ((Get-Date).Year + 1)) { return @{ Date=$date; Source="nome" } }
        } catch { }
    }
    return @{ Date=(Get-Item -LiteralPath $Path).LastWriteTime; Source="arquivo" }
}

function Get-UniqueTarget([string]$Folder, [string]$Name, [long]$Size) {
    $target = Join-Path $Folder $Name
    if (-not (Test-Path -LiteralPath $target)) { return $target }
    if ((Get-Item -LiteralPath $target).Length -eq $Size) { return $target }
    $stem = [IO.Path]::GetFileNameWithoutExtension($Name); $ext = [IO.Path]::GetExtension($Name); $n = 2
    do { $target = Join-Path $Folder ("{0} ({1}){2}" -f $stem,$n,$ext); $n++ } while (Test-Path -LiteralPath $target)
    return $target
}

$form = New-Object Windows.Forms.Form
$form.Text = "Backup da Galeria Android"
$form.Size = New-Object Drawing.Size(780,590)
$form.MinimumSize = New-Object Drawing.Size(700,520)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object Drawing.Font("Segoe UI",10)

$title = New-Object Windows.Forms.Label
$title.Text = "Backup da galeria do Android"; $title.Font = New-Object Drawing.Font("Segoe UI",18,[Drawing.FontStyle]::Bold)
$title.Location = New-Object Drawing.Point(20,18); $title.AutoSize = $true; $form.Controls.Add($title)
$subtitle = New-Object Windows.Forms.Label
$subtitle.Text = "Copia sem apagar nada e organiza automaticamente por ano e mês."
$subtitle.Location = New-Object Drawing.Point(22,56); $subtitle.AutoSize = $true; $form.Controls.Add($subtitle)

$deviceLabel = New-Object Windows.Forms.Label
$deviceLabel.Text = "Celular: ainda não verificado"; $deviceLabel.Location = New-Object Drawing.Point(22,100); $deviceLabel.Size = New-Object Drawing.Size(520,28); $form.Controls.Add($deviceLabel)
$verify = New-Object Windows.Forms.Button
$verify.Text = "Verificar conexão"; $verify.Location = New-Object Drawing.Point(575,94); $verify.Size = New-Object Drawing.Size(160,34); $form.Controls.Add($verify)

$destLabel = New-Object Windows.Forms.Label
$destLabel.Text = "Pasta de destino:"; $destLabel.Location = New-Object Drawing.Point(22,146); $destLabel.AutoSize = $true; $form.Controls.Add($destLabel)
$dest = New-Object Windows.Forms.TextBox
$dest.Text = Join-Path ([Environment]::GetFolderPath("MyPictures")) "Backup do celular"
$dest.Location = New-Object Drawing.Point(22,172); $dest.Size = New-Object Drawing.Size(610,30); $form.Controls.Add($dest)
$choose = New-Object Windows.Forms.Button
$choose.Text = "Escolher..."; $choose.Location = New-Object Drawing.Point(642,169); $choose.Size = New-Object Drawing.Size(93,34); $form.Controls.Add($choose)

$start = New-Object Windows.Forms.Button
$start.Text = "Iniciar backup"; $start.Location = New-Object Drawing.Point(22,220); $start.Size = New-Object Drawing.Size(145,38); $start.Enabled = $false; $form.Controls.Add($start)
$cancel = New-Object Windows.Forms.Button
$cancel.Text = "Parar com segurança"; $cancel.Location = New-Object Drawing.Point(177,220); $cancel.Size = New-Object Drawing.Size(175,38); $cancel.Enabled = $false; $form.Controls.Add($cancel)
$progressText = New-Object Windows.Forms.Label
$progressText.Location = New-Object Drawing.Point(590,229); $progressText.Size = New-Object Drawing.Size(145,25); $progressText.TextAlign = "MiddleRight"; $form.Controls.Add($progressText)
$progress = New-Object Windows.Forms.ProgressBar
$progress.Location = New-Object Drawing.Point(22,272); $progress.Size = New-Object Drawing.Size(713,22); $form.Controls.Add($progress)
$status = New-Object Windows.Forms.Label
$status.Text = "Conecte o celular, desbloqueie e clique em Verificar conexão."
$status.Location = New-Object Drawing.Point(22,302); $status.Size = New-Object Drawing.Size(713,28); $form.Controls.Add($status)
$log = New-Object Windows.Forms.TextBox
$log.Location = New-Object Drawing.Point(22,335); $log.Size = New-Object Drawing.Size(713,190); $log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = "Vertical"; $log.Font = New-Object Drawing.Font("Consolas",9); $form.Controls.Add($log)

$choose.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Escolha onde guardar o backup"
    if ($dialog.ShowDialog() -eq "OK") { $dest.Text = $dialog.SelectedPath }
})

$verify.Add_Click({
    if (-not (Test-Path -LiteralPath $script:Adb)) { [Windows.Forms.MessageBox]::Show("O componente ADB não foi encontrado.", $form.Text, "OK", "Error"); return }
    $verify.Enabled = $false; $status.Text = "Verificando o celular..."; $form.Refresh()
    $result = Invoke-Adb @("devices", "-l")
    $lines = $result.Output -split "`n"
    $authorized = @($lines | Where-Object { $_ -match '^([^\s]+)\s+device(?:\s|$)' })
    $unauthorized = @($lines | Where-Object { $_ -match '\sunauthorized(?:\s|$)' })
    if ($unauthorized.Count) { $deviceLabel.Text = "Celular: autorize este computador na tela do aparelho"; $status.Text = "Aceite a mensagem de depuração USB e tente novamente." }
    elseif ($authorized.Count -eq 1) {
        $script:Serial = ([regex]::Match($authorized[0], '^([^\s]+)')).Groups[1].Value
        $model = Invoke-Adb @("-s",$script:Serial,"shell","getprop","ro.product.model")
        $deviceLabel.Text = "Conectado: " + $model.Output.Trim(); $status.Text = "Celular pronto para o backup."; $start.Enabled = $true
    } elseif ($authorized.Count -gt 1) { $deviceLabel.Text = "Celular: há mais de um conectado"; $status.Text = "Deixe somente um aparelho conectado." }
    else { $deviceLabel.Text = "Celular: não encontrado"; $status.Text = "Confira o cabo, o modo USB e a depuração USB." }
    $verify.Enabled = $true
})

$worker = New-Object ComponentModel.BackgroundWorker
$worker.WorkerReportsProgress = $true
$worker.WorkerSupportsCancellation = $true
$worker.Add_DoWork({ param($sender,$e)
    $root = $e.Argument.Root; $serial = $e.Argument.Serial
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $stage = Join-Path $root ".transferindo"; New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $manifestPath = Join-Path $root ".backup-celular.json"
    $manifest = @{}
    if (Test-Path -LiteralPath $manifestPath) { try { (Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $manifest[$_.Name]=$_.Value } } catch {} }
    $files = New-Object Collections.Generic.HashSet[string]
    foreach ($source in $script:Sources) {
        if ($sender.CancellationPending) { $e.Cancel=$true; return }
        $sender.ReportProgress(0, @{Kind="status";Text="Procurando arquivos em $source..."})
        $scan = Invoke-Adb @("-s",$serial,"shell","find",$source,"-type","f")
        foreach ($line in ($scan.Output -split "`n")) {
            $remote=$line.Trim()
            if ($remote -notlike '/sdcard/*') { continue }
            $ext=[IO.Path]::GetExtension($remote).ToLowerInvariant()
            if ($script:Extensions -contains $ext -and $remote -notmatch '/\.thumbnails/') { [void]$files.Add($remote) }
        }
    }
    $all = @($files | Sort-Object); $copied=0; $skipped=0; $failures=@(); $total=$all.Count
    for ($i=0; $i -lt $total; $i++) {
        if ($sender.CancellationPending) { $e.Cancel=$true; break }
        $remote=$all[$i]; $name=[IO.Path]::GetFileName($remote)
        $sender.ReportProgress([int](100*($i+1)/[math]::Max($total,1)), @{Kind="file";Current=$i+1;Total=$total;Name=$name})
        if ($manifest.ContainsKey($remote) -and (Test-Path -LiteralPath $manifest[$remote].Path) -and (Get-Item -LiteralPath $manifest[$remote].Path).Length -eq $manifest[$remote].Size) { $skipped++; continue }
        $partial=Join-Path $stage (("{0:D8}_" -f ($i+1))+$name)
        try {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            $pull=Invoke-Adb @("-s",$serial,"pull",$remote,$partial)
            if ($pull.Code -ne 0 -or -not (Test-Path -LiteralPath $partial) -or (Get-Item -LiteralPath $partial).Length -eq 0) { throw "Cópia incompleta: $($pull.Output)" }
            $info=Get-RecordedDate $partial $name; $folder=Join-Path (Join-Path $root $info.Date.ToString("yyyy")) $info.Date.ToString("MM")
            New-Item -ItemType Directory -Force -Path $folder | Out-Null
            $size=(Get-Item -LiteralPath $partial).Length; $target=Get-UniqueTarget $folder $name $size
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $partial -Force } else { Move-Item -LiteralPath $partial -Destination $target }
            $manifest[$remote]=@{Path=$target;Size=$size}; $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            $copied++; $sender.ReportProgress(0,@{Kind="log";Text=("{0}\{1}\{2} ({3})" -f $info.Date.ToString("yyyy"),$info.Date.ToString("MM"),[IO.Path]::GetFileName($target),$info.Source)})
        } catch { $failures += @{arquivo=$remote;erro=$_.Exception.Message}; Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
    $report=@{copiados=$copied;ignorados=$skipped;falhas=$failures;data=(Get-Date).ToString("s")}
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root "ultimo-relatorio.json") -Encoding UTF8
    $e.Result=$report
})
$worker.Add_ProgressChanged({ param($sender,$e)
    $data=$e.UserState
    if ($data.Kind -eq "status") { $status.Text=$data.Text }
    elseif ($data.Kind -eq "file") { $progress.Value=$e.ProgressPercentage; $progressText.Text="$($data.Current) de $($data.Total)"; $status.Text="Copiando $($data.Name)" }
    elseif ($data.Kind -eq "log") { $log.AppendText($data.Text+"`r`n") }
})
$worker.Add_RunWorkerCompleted({ param($sender,$e)
    $start.Enabled=$true; $verify.Enabled=$true; $cancel.Enabled=$false
    if ($e.Error) { $status.Text="O backup não pôde continuar."; [Windows.Forms.MessageBox]::Show($e.Error.Message,$form.Text,"OK","Error") }
    elseif ($e.Cancelled) { $status.Text="Backup interrompido com segurança. Execute novamente para continuar."; [Windows.Forms.MessageBox]::Show($status.Text,$form.Text) }
    else { $r=$e.Result; $status.Text="Backup concluído."; [Windows.Forms.MessageBox]::Show("Backup concluído.`n`nCopiados: $($r.copiados)`nJá existentes: $($r.ignorados)`nFalhas: $($r.falhas.Count)",$form.Text) }
})

$script:BackupProcess = $null
$script:ProgressFile = Join-Path ([IO.Path]::GetTempPath()) ("backup-galeria-" + [guid]::NewGuid().ToString("N") + ".json")
$script:CancelFile = $script:ProgressFile + ".cancel"
$script:LastLog = ""
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
    $stateFiles = Get-StateFiles
    $latest = $stateFiles | Sort-Object LastWriteTimeUtc,Name -Descending | Select-Object -First 1
    if (-not $latest) { return }
    try { $state = Get-Content -Raw -LiteralPath $latest.FullName -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return }
    $stateFiles | Where-Object { $_.FullName -ne $latest.FullName } | Remove-Item -Force -ErrorAction SilentlyContinue
    if ($state.Kind -eq "status") { $status.Text = $state.Text }
    elseif ($state.Kind -eq "file") {
        $total=[math]::Max([int]$state.Total,1); $progress.Value=[math]::Min(100,[int](100*[int]$state.Current/$total))
        $progressText.Text="$($state.Current) de $($state.Total)"
        $details=""
        if ([long]$state.Size -gt 0) { $details=(" - {0:N1} MB" -f (([long]$state.Size) / 1MB)) }
        if ($state.StartedAt) { try { $elapsed=(Get-Date)-[datetime]::Parse($state.StartedAt); $details += (" - {0:mm\:ss}" -f $elapsed) } catch {} }
        $status.Text="Copiando $($state.Name)$details"
        if ($state.Log -and $state.Log -ne $script:LastLog) { $log.AppendText($state.Log+"`r`n"); $script:LastLog=$state.Log }
    } elseif ($state.Kind -in @("done","cancelled","fatal")) {
        $timer.Stop(); $start.Enabled=$true; $verify.Enabled=$true; $cancel.Enabled=$false
        if ($state.Kind -eq "done") { $status.Text="Backup concluído."; [Windows.Forms.MessageBox]::Show("Backup concluído.`n`nCopiados: $($state.Copied)`nJá existentes: $($state.Skipped)`nFalhas: $($state.Failures)",$form.Text) }
        elseif ($state.Kind -eq "cancelled") { $status.Text="Backup interrompido com segurança. Execute novamente para continuar."; [Windows.Forms.MessageBox]::Show($status.Text,$form.Text) }
        else { $status.Text="O backup não pôde continuar."; [Windows.Forms.MessageBox]::Show($state.Error,$form.Text,"OK","Error") }
        Clear-StateFiles
        Remove-Item -LiteralPath $script:CancelFile -Force -ErrorAction SilentlyContinue
        $script:BackupProcess=$null
    }
})

$start.Add_Click({
    if ([string]::IsNullOrWhiteSpace($dest.Text)) { return }
    Clear-StateFiles
    Remove-Item -LiteralPath $script:CancelFile -Force -ErrorAction SilentlyContinue
    $start.Enabled=$false; $verify.Enabled=$false; $cancel.Enabled=$true; $log.Clear(); $progress.Value=0; $progressText.Text=""; $script:LastLog=""
    $workerScript=Join-Path $script:Base "BackupGaleriaWorker.ps1"
    $quotedWorker='"'+$workerScript+'"'; $quotedRoot='"'+$dest.Text+'"'; $quotedAdb='"'+$script:Adb+'"'; $quotedProgress='"'+$script:ProgressFile+'"'; $quotedCancel='"'+$script:CancelFile+'"'
    $arguments=@("-NoProfile","-ExecutionPolicy","Bypass","-File",$quotedWorker,"-Serial",$script:Serial,"-Root",$quotedRoot,"-Adb",$quotedAdb,"-ProgressFile",$quotedProgress,"-CancelFile",$quotedCancel)
    $script:BackupProcess=Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $timer.Start()
})
$cancel.Add_Click({
    $cancel.Enabled=$false; $status.Text="Terminando o arquivo atual e parando com segurança..."
    Set-Content -LiteralPath $script:CancelFile -Value "cancelar" -Encoding ASCII
})
$form.Add_FormClosing({ param($sender,$e) if ($script:BackupProcess -and -not $script:BackupProcess.HasExited) { $e.Cancel=$true; [Windows.Forms.MessageBox]::Show("Clique em 'Parar com segurança' antes de fechar.",$form.Text) } })

[void]$form.ShowDialog()


param(
    [Parameter(Mandatory=$true)][string]$Serial,
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Adb,
    [Parameter(Mandatory=$true)][string]$ProgressFile,
    [Parameter(Mandatory=$true)][string]$CancelFile
)

$ErrorActionPreference = "Stop"
$sources = @(
    "/sdcard/DCIM", "/sdcard/Pictures", "/sdcard/Movies",
    "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images",
    "/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video"
)
$extensions = @(".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif", ".dng", ".mp4", ".mov", ".m4v", ".3gp", ".mkv", ".avi", ".webm")

function Send-State([hashtable]$State) {
    # Cada atualização é um arquivo independente. Assim, a interface nunca lê
    # o mesmo arquivo que o processo de backup está escrevendo.
    $sequence = [datetime]::UtcNow.Ticks
    $statePath = $ProgressFile + "." + $sequence + "." + [guid]::NewGuid().ToString("N") + ".state"
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
}
function Invoke-Adb([string[]]$Arguments) {
    # Pastas opcionais (por exemplo, WhatsApp) podem não existir. O ADB escreve
    # esse aviso em stderr; capture-o sem transformar a ausência em erro fatal.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $Adb @Arguments 2>&1
        $code = $LASTEXITCODE
        return @{ Code=$code; Output=($output -join "`n") }
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}
function Quote-ProcessArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
function Invoke-AdbPull([string]$Remote, [string]$Local) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Adb
    $parts = @("-s", $Serial, "pull", $Remote, $Local) | ForEach-Object { Quote-ProcessArgument $_ }
    $info.Arguments = $parts -join " "
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { return @{Code=1;Output="Não foi possível iniciar a cópia."} }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(250)) {
            if (Test-Path -LiteralPath $CancelFile) {
                try { $process.Kill() } catch { }
                $process.WaitForExit()
                return @{Code=1223;Output="Cópia interrompida pelo usuário."}
            }
        }
        return @{Code=$process.ExitCode;Output=(($stdout.Result + "`n" + $stderr.Result).Trim())}
    } finally { $process.Dispose() }
}
function Get-RecordedDate([string]$Path, [string]$Name) {
    if ([IO.Path]::GetExtension($Path) -match '^\.(jpg|jpeg)$') {
        try {
            Add-Type -AssemblyName System.Drawing
            $image=[Drawing.Image]::FromFile($Path)
            try {
                $prop=$image.GetPropertyItem(36867); $text=[Text.Encoding]::ASCII.GetString($prop.Value).Trim([char]0); $parsed=[datetime]::MinValue
                if ([datetime]::TryParseExact($text,"yyyy:MM:dd HH:mm:ss",$null,[Globalization.DateTimeStyles]::None,[ref]$parsed)) { return @{Date=$parsed;Source="metadata"} }
            } finally { $image.Dispose() }
        } catch { }
    }
    $match=[regex]::Match($Name,'(?<!\d)((?:19|20)\d{2})[-_]?([01]\d)[-_]?([0-3]\d)(?!\d)')
    if ($match.Success) {
        try { $date=[datetime]::new([int]$match.Groups[1].Value,[int]$match.Groups[2].Value,[int]$match.Groups[3].Value); if ($date.Year -le ((Get-Date).Year+1)) { return @{Date=$date;Source="nome"} } } catch { }
    }
    return @{Date=(Get-Item -LiteralPath $Path).LastWriteTime;Source="arquivo"}
}
function Get-UniqueTarget([string]$Folder,[string]$Name,[long]$Size) {
    $target=Join-Path $Folder $Name
    if (-not (Test-Path -LiteralPath $target)) { return $target }
    if ((Get-Item -LiteralPath $target).Length -eq $Size) { return $target }
    $stem=[IO.Path]::GetFileNameWithoutExtension($Name); $ext=[IO.Path]::GetExtension($Name); $n=2
    do { $target=Join-Path $Folder ("{0} ({1}){2}" -f $stem,$n,$ext); $n++ } while (Test-Path -LiteralPath $target)
    return $target
}

try {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $stage=Join-Path $Root ".transferindo"; New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $manifestPath=Join-Path $Root ".backup-celular.json"; $manifest=@{}
    if (Test-Path -LiteralPath $manifestPath) { try { (Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $manifest[$_.Name]=$_.Value } } catch {} }
    $files=New-Object Collections.Generic.HashSet[string]
    foreach ($source in $sources) {
        if (Test-Path -LiteralPath $CancelFile) { Send-State @{Kind="cancelled"}; exit 2 }
        Send-State @{Kind="status";Text="Procurando arquivos em $source..."}
        $scan=Invoke-Adb @("-s",$Serial,"shell","find",$source,"-type","f")
        foreach ($line in ($scan.Output -split "`n")) {
            $remote=$line.Trim()
            if ($remote -notlike '/sdcard/*') { continue }
            if ($extensions -contains [IO.Path]::GetExtension($remote).ToLowerInvariant() -and $remote -notmatch '/\.thumbnails/') { [void]$files.Add($remote) }
        }
    }
    $all=@($files|Sort-Object); $copied=0; $skipped=0; $failures=@(); $total=$all.Count
    for ($i=0;$i -lt $total;$i++) {
        if (Test-Path -LiteralPath $CancelFile) { Send-State @{Kind="cancelled";Copied=$copied;Skipped=$skipped;Failures=$failures.Count}; exit 2 }
        $remote=$all[$i]; $name=[IO.Path]::GetFileName($remote)
        $remoteSize = 0L
        $stat = Invoke-Adb @("-s",$Serial,"shell","stat","-c","%s",$remote)
        if ($stat.Code -eq 0) { $number = 0L; if ([long]::TryParse($stat.Output.Trim(),[ref]$number)) { $remoteSize=$number } }
        $startedAt=(Get-Date).ToString("o")
        Send-State @{Kind="file";Current=$i+1;Total=$total;Name=$name;Size=$remoteSize;StartedAt=$startedAt;Copied=$copied;Skipped=$skipped}
        if ($manifest.ContainsKey($remote) -and (Test-Path -LiteralPath $manifest[$remote].Path) -and (Get-Item -LiteralPath $manifest[$remote].Path).Length -eq $manifest[$remote].Size) { $skipped++; continue }
        $partial=Join-Path $stage (("{0:D8}_" -f ($i+1))+$name)
        try {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            $pull=Invoke-AdbPull $remote $partial
            if ($pull.Code -ne 0 -or -not (Test-Path -LiteralPath $partial) -or (Get-Item -LiteralPath $partial).Length -eq 0) { throw "Cópia incompleta: $($pull.Output)" }
            $info=Get-RecordedDate $partial $name; $folder=Join-Path (Join-Path $Root $info.Date.ToString("yyyy")) $info.Date.ToString("MM")
            New-Item -ItemType Directory -Force -Path $folder|Out-Null
            $size=(Get-Item -LiteralPath $partial).Length; $target=Get-UniqueTarget $folder $name $size
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $partial -Force } else { Move-Item -LiteralPath $partial -Destination $target }
            $manifest[$remote]=@{Path=$target;Size=$size}; $manifest|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $manifestPath -Encoding UTF8
            $copied++; Send-State @{Kind="file";Current=$i+1;Total=$total;Name=$name;Copied=$copied;Skipped=$skipped;Log=("{0}\{1}\{2} ({3})" -f $info.Date.ToString("yyyy"),$info.Date.ToString("MM"),[IO.Path]::GetFileName($target),$info.Source)}
        } catch { $failures+=@{arquivo=$remote;erro=$_.Exception.Message}; Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
    $report=@{copiados=$copied;ignorados=$skipped;falhas=$failures;data=(Get-Date).ToString("s")}
    $report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $Root "ultimo-relatorio.json") -Encoding UTF8
    Send-State @{Kind="done";Copied=$copied;Skipped=$skipped;Failures=$failures.Count}
} catch {
    Send-State @{Kind="fatal";Error=$_.Exception.Message}
    exit 1
}


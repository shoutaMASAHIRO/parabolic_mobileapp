$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$backendPath = Join-Path $scriptPath "backend"
$outPath = Join-Path $backendPath "out"

if (!(Test-Path $outPath)) { New-Item -ItemType Directory -Path $outPath }

Push-Location $backendPath
try {
    javac src\Main.java -d out
    if ($LASTEXITCODE -eq 0) {
        java -cp out Main @args
    }
} finally {
    Pop-Location
}

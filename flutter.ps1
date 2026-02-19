$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Push-Location (Join-Path $scriptPath "frontend")
try {
    & "C:\Users\RYZEN5 5500\dev\flutter_sdk\flutter\bin\flutter.bat" @args
} finally {
    Pop-Location
}

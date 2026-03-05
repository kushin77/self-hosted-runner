# CI/CD Runner Bootstrap Script (Windows PowerShell)
# Usage: .\bootstrap.ps1
# Requires: PowerShell 5.0+, Administrator privileges

param(
    [string]$RunnerRepo = "https://github.com/YOUR_ORG/self-hosted-runner",
    [string]$RunnerToken = "",
    [string]$RunnerUrl = "https://github.com",
    [string]$RunnerLabels = "windows,self-hosted",
    [string]$RunnerHome = "C:\actions-runner"
)

# Color output helpers
function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
    exit 1
}

function Write-Status {
    param([string]$Message)
    Write-Host "[•] $Message" -ForegroundColor Yellow
}

# Verify admin privileges
$isAdmin = [bool]([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544')
if (-not $isAdmin) {
    Write-Error "Administrator privileges required. Run as Administrator."
}

Write-Status "CI/CD Runner Bootstrap for Windows"

# 1. Verify system requirements
Write-Status "Step 1: Verifying system requirements..."
$osVersion = [System.Environment]::OSVersion
if ($osVersion.Major -ge 10) {
    Write-Success "Windows version: $osVersion"
} else {
    Write-Error "Windows 10 or later required"
}

$cpuCount = (Get-WmiObject -Class Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
if ($cpuCount -ge 2) {
    Write-Success "CPU cores: $cpuCount"
} else {
    Write-Error "At least 2 CPU cores required"
}

$ramGb = [Math]::Round((Get-WmiObject -Class Win32_OperatingSystem).TotalVisibleMemorySize / 1024 / 1024)
if ($ramGb -ge 4) {
    Write-Success "RAM: ${ramGb}GB"
} else {
    Write-Error "At least 4GB RAM required"
}

# 2. Install Chocolatey if missing
Write-Status "Step 2: Preparing package manager..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Status "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# 3. Install dependencies
Write-Status "Step 3: Installing dependencies..."
choco install -y `
    git `
    curl `
    jq `
    docker-desktop `
    openssl `
    awscli

# 4. Create runner directory
Write-Status "Step 4: Creating runner directories..."
if (-not (Test-Path $RunnerHome)) {
    New-Item -ItemType Directory -Path $RunnerHome -Force | Out-Null
    Write-Success "Created runner home: $RunnerHome"
}

# 5. Clone platform repo
Write-Status "Step 5: Cloning runner platform repository..."
$projectRoot = Split-Path -Parent $RunnerHome
if (Test-Path "$projectRoot\cicd-runner-platform\.git") {
    Write-Status "Repository already exists, pulling latest..."
    Push-Location "$projectRoot\cicd-runner-platform"
    git pull origin main
    Pop-Location
} else {
    git clone $RunnerRepo "$projectRoot\cicd-runner-platform"
}

# 6. Install GitHub Actions Runner
Write-Status "Step 6: Installing GitHub Actions runner..."
& "$projectRoot\cicd-runner-platform\runner\install-runner.ps1"

# 7. Register runner
Write-Status "Step 7: Registering runner..."
& "$projectRoot\cicd-runner-platform\runner\register-runner.ps1" `
    -Url $RunnerUrl `
    -Token $RunnerToken `
    -Labels $RunnerLabels

# 8. Setup Windows scheduled task
Write-Status "Step 8: Configuring Windows scheduled task..."
$actionPath = "$RunnerHome\run.cmd"
$action = New-ScheduledTaskAction -Execute $actionPath
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Description "GitHub Actions Runner"
Register-ScheduledTask -TaskName "GitHub-Actions-Runner" -InputObject $task -Force
Write-Success "Scheduled task created: GitHub-Actions-Runner"

# 9. Start runner
Write-Status "Step 9: Starting runner service..."
Start-ScheduledTask -TaskName "GitHub-Actions-Runner"

Write-Success "Bootstrap complete! Runner will start automatically."
Write-Status "Monitor with: Get-ScheduledTaskInfo -TaskName GitHub-Actions-Runner"

[CmdletBinding()]
param(
    [string]$PromptFile,
    [string]$Out,
    [string]$Model = 'gpt-image-2',
    [string]$Size = '1536x864',
    [ValidateSet('low', 'medium', 'high', 'auto')][string]$Quality = 'high',
    [string]$Python,
    [string]$CodexRoot,
    [string[]]$ReferenceImages = @(),
    [switch]$Probe,
    [switch]$DryRun,
    [switch]$UseSystemProxy
)

$ErrorActionPreference = 'Stop'
if ($Probe -and $DryRun) { throw 'Choose -Probe or -DryRun, not both.' }
if (-not $CodexRoot) {
    $CodexRoot = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
}
$configPath = Join-Path $CodexRoot 'config.toml'
$sections = @{}
$sectionName = ''
$sections[$sectionName] = @{}
# Deliberately limited to normal provider tables and simple quoted strings.
foreach ($configLine in Get-Content -LiteralPath $configPath) {
    if ($configLine -match '^\s*\[([^\]]+)\]\s*(?:#.*)?$') {
        $sectionName = $Matches[1].Trim()
        if (-not $sections.ContainsKey($sectionName)) { $sections[$sectionName] = @{} }
    } elseif ($configLine -match '^\s*(model_provider|base_url|env_key)\s*=\s*"([^"\\]*)"\s*(?:#.*)?$') {
        $sections[$sectionName][$Matches[1]] = $Matches[2]
    } elseif ($configLine -match "^\s*(model_provider|base_url|env_key)\s*=\s*'([^']*)'\s*(?:#.*)?$") {
        $sections[$sectionName][$Matches[1]] = $Matches[2]
    }
}
$provider = $sections['']['model_provider']
if (-not $provider -or $provider -notmatch '(?i)(cliproxyapi|cpa)') {
    throw 'Top-level model_provider must identify CPA/CLIProxyAPI. Inspect the active configuration; do not guess an endpoint.'
}
$providerSettings = $sections["model_providers.$provider"]
if (-not $providerSettings) { $providerSettings = $sections[('model_providers."{0}"' -f $provider)] }
if (-not $providerSettings -or -not $providerSettings['base_url']) { throw 'Missing supported CPA provider base_url.' }
$baseUrl = $providerSettings['base_url'].TrimEnd('/')
$baseUri = [Uri]$baseUrl
if (-not $baseUri.IsAbsoluteUri -or $baseUri.UserInfo -or $baseUri.Query -or $baseUri.Fragment) {
    throw 'CPA base_url must be an absolute URL without credentials, query, or fragment.'
}
if ($baseUri.Scheme -ne 'https' -and -not ($baseUri.Scheme -eq 'http' -and $baseUri.IsLoopback)) {
    throw 'CPA base_url must use HTTPS (HTTP is allowed only for loopback).'
}
if ($baseUri.AbsolutePath.TrimEnd('/') -notmatch '/v1$') { throw 'Expected a configured CPA base_url ending in /v1.' }

if (-not $Probe) {
    if (-not $PromptFile -or -not $Out) { throw 'Generation requires -PromptFile and -Out.' }
    $promptPath = (Resolve-Path -LiteralPath $PromptFile).Path
    if (Test-Path -LiteralPath $Out) { throw 'Output already exists; choose a new filename.' }
    if ([IO.Path]::GetExtension($Out) -ne '.png') { throw 'Use a .png output filename.' }
    if (-not $Python) {
        $Python = if (Test-Path -LiteralPath '.venv/Scripts/python.exe') {
            (Resolve-Path -LiteralPath '.venv/Scripts/python.exe').Path
        } else { (Get-Command python -ErrorAction Stop).Source }
    }
    $imageCli = Join-Path $CodexRoot 'skills/.system/imagegen/scripts/image_gen.py'
    if (-not (Test-Path -LiteralPath $imageCli)) { throw 'Bundled imagegen/scripts/image_gen.py is missing. Install the imagegen skill first.' }
    $operation = if ($ReferenceImages.Count -gt 0) { 'edit' } else { 'generate' }
    $cliArgs = @($imageCli, $operation, '--model', $Model, '--prompt-file', $promptPath,
        '--size', $Size, '--quality', $Quality, '--out', $Out, '--no-augment')
    foreach ($referenceImage in $ReferenceImages) {
        $referencePath = (Resolve-Path -LiteralPath $referenceImage).Path
        $cliArgs += @('--image', $referencePath)
    }
    if ($DryRun) {
        & $Python @cliArgs --dry-run
        if ($LASTEXITCODE -ne 0) { throw "Image CLI dry run failed (exit $LASTEXITCODE)." }
        return
    }
    & $Python -c 'import openai'
    if ($LASTEXITCODE -ne 0) { throw 'Install the OpenAI SDK into the selected Python environment first. See SKILL.md.' }
}

$apiKey = $null
if ($providerSettings['env_key']) {
    $apiKey = [Environment]::GetEnvironmentVariable($providerSettings['env_key'], 'Process')
} else {
    $authPath = Join-Path $CodexRoot 'auth.json'
    if (Test-Path -LiteralPath $authPath) {
        $apiKey = (Get-Content -Raw -LiteralPath $authPath | ConvertFrom-Json).OPENAI_API_KEY
    }
}
if (-not $apiKey) { throw 'No static CPA API key found in provider env_key or Codex auth.json. Configure it locally; do not paste it in chat.' }

$previousEnvironment = @{}
foreach ($envName in @('OPENAI_API_KEY', 'OPENAI_BASE_URL', 'NO_PROXY')) {
    $previousEnvironment[$envName] = [Environment]::GetEnvironmentVariable($envName, 'Process')
}
try {
    $env:OPENAI_API_KEY = $apiKey
    $env:OPENAI_BASE_URL = $baseUrl
    if (-not $UseSystemProxy) {
        $env:NO_PROXY = (@($previousEnvironment['NO_PROXY'], $baseUri.DnsSafeHost) |
            Where-Object { $_ }) -join ','
    }
    if ($Probe) {
        $requestArgs = @{
            Uri = "$baseUrl/models"
            Headers = @{ Authorization = "Bearer $apiKey" }
            TimeoutSec = 30
            MaximumRedirection = 0
        }
        if (-not $UseSystemProxy -and (Get-Command Invoke-RestMethod).Parameters.ContainsKey('NoProxy')) {
            $requestArgs['NoProxy'] = $true
        }
        $modelList = Invoke-RestMethod @requestArgs
        $modelList.data | Select-Object -ExpandProperty id
    } else {
        & $Python @cliArgs
        if ($LASTEXITCODE -ne 0) { throw "CPA generation failed (exit $LASTEXITCODE). See the API error above; do not retry blindly." }
    }
} finally {
    foreach ($envName in $previousEnvironment.Keys) {
        if ($null -eq $previousEnvironment[$envName]) {
            Remove-Item -LiteralPath "Env:$envName" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($envName, $previousEnvironment[$envName], 'Process')
        }
    }
    $apiKey = $null
}

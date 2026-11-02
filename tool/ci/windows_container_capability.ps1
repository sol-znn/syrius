# Read only finite facts from a fresh GitHub-hosted Windows Arm VM.
# This does not enable a feature, install software, start WSL/Docker or qualify
# nested virtualization, the x64 wallet, its DLL, chain-321 or Linux containers.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$failure = 'CAPABILITY_REFUSED'
function Mark-Capability([string] $stage) {
  [Console]::Out.WriteLine('SYRIUS_CAPABILITY_STAGE:' + $stage)
  [Console]::Out.Flush()
}
function Read-SourceGit([string[]] $arguments) {
  $lines = @(& git --no-pager --no-lazy-fetch -c core.fsmonitor=false -c gc.auto=0 @arguments 2>$null)
  $code = $LASTEXITCODE
  $text = [string]::Join("`n", [string[]] $lines)
  if ($code -ne 0 -or $text.Length -gt 4096) { throw 'SOURCE_REFUSED' }
  return $text
}
function Read-Boolean([object] $item, [string] $name) {
  if ($null -eq $item) { return $null }
  $value = $item.$name
  if ($value -is [bool]) { return $value }
  return $null
}
function Read-CpuConsensus([object[]] $items, [string] $name) {
  if ($items.Count -lt 1 -or $items.Count -gt 64) { return $null }
  $first = Read-Boolean $items[0] $name
  if ($null -eq $first) { return $null }
  foreach ($item in $items) {
    $value = Read-Boolean $item $name
    if ($null -eq $value -or $value -cne $first) { return $null }
  }
  return $first
}
function Read-Feature([string] $name) {
  try {
    $rows = @(Get-CimInstance -ClassName Win32_OptionalFeature -Filter ("Name='" + $name + "'") -Property InstallState -OperationTimeoutSec 5 -ErrorAction Stop)
    if ($rows.Count -ne 1) { return 'unknown' }
    switch ($rows[0].InstallState) {
      1 { return 'enabled' }
      2 { return 'disabled' }
      3 { return 'absent' }
      default { return 'unknown' }
    }
  } catch { return 'unknown' }
}
function Read-CommandPresence([string] $name) {
  try {
    $found = @(Get-Command -Name $name -CommandType Application -ErrorAction Stop)
    return ($found.Count -gt 0)
  } catch [System.Management.Automation.CommandNotFoundException] {
    return $false
  } catch { return $null }
}
function Read-Architecture([object] $value) {
  $text = $value.ToString().ToLowerInvariant()
  if (@('arm64', 'x64', 'x86', 'arm') -ccontains $text) { return $text }
  return 'unknown'
}
try {
  $failure = 'ENVIRONMENT_REFUSED'
  if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
      $env:RUNNER_ARCH -cne 'ARM64' -or $env:GITHUB_REPOSITORY -cne 'edgepillar/syrius' -or
      $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
      $env:SYRIUS_WINDOWS_CONTAINER_CAPABILITY -cne 'true' -or
      -not [regex]::IsMatch([string]$env:GITHUB_SHA, '\A[a-f0-9]{40}\z') -or
      -not [regex]::IsMatch([string]$env:GITHUB_RUN_ID, '\A[1-9][0-9]{0,19}\z') -or
      $env:GITHUB_RUN_ATTEMPT -cne '1') { throw 'ENVIRONMENT_REFUSED' }
  Mark-Capability 'entry'
  $failure = 'SOURCE_REFUSED'
  $head = Read-SourceGit @('rev-parse', 'HEAD')
  $tree = Read-SourceGit @('rev-parse', 'HEAD^{tree}')
  if ($head -cne $env:GITHUB_SHA -or -not [regex]::IsMatch($tree, '\A[a-f0-9]{40}\z') -or
      (Read-SourceGit @('status', '--porcelain=v1', '--untracked-files=all')).Length -ne 0) { throw 'SOURCE_REFUSED' }
  Mark-Capability 'source_before'
  $failure = 'CAPABILITY_REFUSED'
  $os = $null; $system = $null; $processors = @()
  try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property ProductType -OperationTimeoutSec 5 -ErrorAction Stop } catch {}
  $product = if ($null -ne $os -and @(1, 2, 3) -contains $os.ProductType) { [int]$os.ProductType } else { $null }
  $osArchitecture = Read-Architecture ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)
  $processArchitecture = Read-Architecture ([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)
  Mark-Capability 'platform'
  try { $system = Get-CimInstance -ClassName Win32_ComputerSystem -Property HypervisorPresent -OperationTimeoutSec 5 -ErrorAction Stop } catch {}
  try { $processors = @(Get-CimInstance -ClassName Win32_Processor -Property VirtualizationFirmwareEnabled,VMMonitorModeExtensions,SecondLevelAddressTranslationExtensions -OperationTimeoutSec 5 -ErrorAction Stop) } catch {}
  $hypervisor = Read-Boolean $system 'HypervisorPresent'
  $firmware = Read-CpuConsensus $processors 'VirtualizationFirmwareEnabled'
  $monitor = Read-CpuConsensus $processors 'VMMonitorModeExtensions'
  $slat = Read-CpuConsensus $processors 'SecondLevelAddressTranslationExtensions'
  Mark-Capability 'virtualization_flags'
  $features = [ordered]@{
    virtual_machine_platform = (Read-Feature 'VirtualMachinePlatform')
    subsystem_for_linux = (Read-Feature 'Microsoft-Windows-Subsystem-Linux')
    hypervisor = (Read-Feature 'Microsoft-Hyper-V-Hypervisor')
  }
  Mark-Capability 'optional_features'
  $wsl = Read-CommandPresence 'wsl.exe'
  $docker = Read-CommandPresence 'docker.exe'
  $desktop = $null
  try {
    if (-not [string]::IsNullOrEmpty($env:ProgramFiles)) {
      $desktop = Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Docker/Docker/Docker Desktop.exe') -PathType Leaf -ErrorAction Stop
    }
  } catch {}
  Mark-Capability 'tool_presence'
  $failure = 'SOURCE_REFUSED'
  if ((Read-SourceGit @('rev-parse', 'HEAD')) -cne $head -or
      (Read-SourceGit @('rev-parse', 'HEAD^{tree}')) -cne $tree -or
      (Read-SourceGit @('status', '--porcelain=v1', '--untracked-files=all')).Length -ne 0) { throw 'SOURCE_REFUSED' }
  Mark-Capability 'source_after'
  $failure = 'CAPABILITY_REFUSED'
  $result = [ordered]@{
    schema = 1; scope = 'github_hosted_windows_container_capability'; status = 'OBSERVED'
    source_sha = $head; source_tree = $tree; run_id = $env:GITHUB_RUN_ID; run_attempt = 1
    product_type = $product; os_architecture = $osArchitecture; process_architecture = $processArchitecture
    hypervisor_present = $hypervisor; firmware_virtualization_flag = $firmware
    vm_monitor_flag = $monitor; slat_flag = $slat; optional_features = $features
    wsl_command_on_path = $wsl; docker_command_on_path = $docker; docker_desktop_standard_file = $desktop
    source_unchanged = $true; native_x86_flag_inference_applied = $false
    nested_virtualization = 'NOT_ESTABLISHED'; docker_linux_mode_qualified = $false
    x64_wallet_qualified = $false; chain321_qualified = $false
    installation_performed = $false; features_changed = $false
    kernel_or_container_started = $false; wallet_or_node_started = $false; downloads_performed = $false
  }
  $json = ConvertTo-Json -InputObject $result -Depth 4 -Compress
  if ($json.Length -gt 8192 -or $json -match '[\r\n]') { throw 'CAPABILITY_REFUSED' }
  Mark-Capability 'complete'
  [Console]::Out.WriteLine('::notice title=Windows container capability::' + $json)
  exit 0
} catch {
  [Console]::Out.WriteLine('::error title=Windows container capability::' + $failure)
  exit 1
}

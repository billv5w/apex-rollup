$DebugPreference = 'Continue'
$ErrorActionPreference = 'Stop'
# This is also the same script that runs on Github via the Github Action configured in .github/workflows
$testInvocation = 'npx sfdx force:apex:test:run -s ApexRollupTestSuite -r human -w 20 -c -d ./tests/apex'
$currentUserAlias = 'apex-rollup-scratch-org'

. .\scripts\string-utils.ps1
. .\scripts\integration-test-large-data-volume.ps1

function Start-Tests() {
  Write-Debug "Deploying metadata ..."
  npx sfdx force:source:deploy -p rollup
  npx sfdx force:source:deploy -p extra-tests

  $currentBranch = Get-Current-Git-Branch
  Write-Debug "Starting test run on branch $currentBranch ..."
  Invoke-Expression $testInvocation
  $testRunId = Get-Content tests/apex/test-run-id.txt
  $specificTestRunJson = Get-Content "tests/apex/test-result-$testRunId.json" | ConvertFrom-Json
  $testFailure = $false
  if ($specificTestRunJson.summary.outcome -eq "Failed") {
    $testFailure = $true
  }

  if ($false -eq $testFailure -And $currentBranch.Contains("main") -eq $false) {
    Start-Integration-Tests
  }

  try {
    Write-Debug "Deleting scratch org ..."
    npx sfdx force:org:delete -p
  } catch {
    Write-Debug "Scratch org deletion failed, continuing ..."
  }

  if ($true -eq $testFailure) {
    throw $specificTestRunJson.summary
  }
}

Write-Debug "Starting build script"

$scratchOrgAllotment = ((npx sfdx force:limits:api:display --json | ConvertFrom-Json).result | Where-Object -Property name -eq "DailyScratchOrgs").remaining

Write-Debug "Total remaining scratch orgs for the day: $scratchOrgAllotment"
Write-Debug "Test command to use: $testInvocation"

$shouldDeployToSandbox = $false

if($scratchOrgAllotment -gt 0) {
  Write-Debug "Beginning scratch org creation"
  # Create Scratch Org
  $scratchOrgCreateMessage = npx sfdx force:org:create -f config/project-scratch-def.json -a $currentUserAlias -s -d 1
  # Sometimes SFDX lies (UTC date problem?) about the number of scratch orgs remaining in a given day
  # The other issue is that this doesn't throw, so we have to test the response message ourselves
  if($scratchOrgCreateMessage -eq 'The signup request failed because this organization has reached its active scratch org limit') {
    throw $1
  }
  # Multi-currency prep
  Write-Debug 'Importing multi-currency config data to scratch org ...'
  npx sfdx force:data:tree:import -f ./config/data/CurrencyTypes.json
  # Run tests
  Start-Tests
} else {
  $shouldDeployToSandbox = $true
}

if($shouldDeployToSandbox) {
  Write-Debug "No scratch orgs remaining, running tests on sandbox"
  # Deploy and test
  Start-Tests
}

Write-Debug "Build + testing finished successfully"


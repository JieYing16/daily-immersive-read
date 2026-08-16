[CmdletBinding()]
param(
    # Push to main even when the repo is checked out on another branch. Off by
    # default: from a feature branch this fast-forwards main to whatever else
    # is on that branch, publishing unreviewed work as a side effect of the
    # daily run.
    [switch]$PushFromAnyBranch
)

$repo = "D:\GitHub\daily-immersive-read"
$files = @("daily_reads.md", "reads.json")
$publishBranch = 'main'

Set-Location $repo

# git writes CRLF warnings and push progress to stderr on success. This script
# runs under run_daily.ps1, whose 'Stop' preference would promote any of those
# lines to a terminating error, so exit codes are checked explicitly instead.
$ErrorActionPreference = 'Continue'

function Invoke-Git {
    <#  Run git, throw on a non-zero exit code, and return stdout only.
        stderr is deliberately not merged into the return value: folding it in
        is what made a clean "git status --porcelain" look like pending changes
        whenever git emitted a CRLF warning.  #>
    param([Parameter(Mandatory)][string[]]$GitArgs)

    $out = & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE."
    }
    return $out
}

# Scope the status check to the files we actually commit, so unrelated edits
# in the working tree neither trigger a commit nor get swept into one.
$statusArgs = @('status', '--porcelain', '--') + $files
$status = Invoke-Git $statusArgs

if (-not $status) {
    Write-Output "No changes to $($files -join ', ') - nothing to commit."
    return
}

$date = Get-Date -Format "yyyy-MM-dd"

Invoke-Git (@('add', '--') + $files) | Out-Null
Invoke-Git @('commit', '-m', "chore: daily reads $date") | Out-Null

# Commit first, push second: if the push is refused below, the day's entries
# are still safely in git rather than lost with the error.
$branch = Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')

if ($branch -ne $publishBranch -and -not $PushFromAnyBranch) {
    # The old "git push origin main" pushed the local main ref no matter where
    # HEAD was, so from a feature branch it reported "Everything up-to-date"
    # and the phone silently never saw a new read. Pushing HEAD:main instead
    # would fix that by fast-forwarding main to this branch - taking every
    # unrelated commit on it along for the ride. Neither is safe to do
    # quietly, so this stops with something actionable in the log.
    throw ("On branch '$branch', not '$publishBranch' - commit made, push skipped. " +
           "Merge or switch to $publishBranch, or re-run with -PushFromAnyBranch " +
           "to fast-forward $publishBranch to '$branch'.")
}

# HEAD:<branch>, not <branch>: push what is actually checked out.
Invoke-Git @('push', 'origin', "HEAD:$publishBranch") | Out-Null

Write-Output "Committed and pushed daily reads for $date."

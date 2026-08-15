$repo = "D:\GitHub\daily-immersive-read"
$files = @("daily_reads.md", "reads.json")

Set-Location $repo

# Scope the status check to the files we actually commit, so unrelated edits
# in the working tree neither trigger a commit nor get swept into one.
$status = git status --porcelain -- $files 2>&1
if ($status) {
    git add -- $files
    $date = Get-Date -Format "yyyy-MM-dd"
    git commit -m "chore: daily reads $date"
    git push origin main
} else {
    Write-Output "No changes to $($files -join ', ') - nothing to commit."
}

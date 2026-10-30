$private = Join-Path $PSScriptRoot 'Private'
$public = Join-Path $PSScriptRoot 'Public'

foreach ($file in Get-ChildItem -Path $private, $public -Filter '*.ps1' -Recurse -File -ErrorAction Ignore) {
    . $file.FullName
}

# Public functions are named after their file.
$exported = Get-ChildItem -Path $public -Filter '*.ps1' -File -ErrorAction Ignore | ForEach-Object BaseName
Export-ModuleMember -Function $exported

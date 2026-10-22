# Règle les options d'import des textures générées à l'exécution :
# compression GPU + mipmaps, et marquage des cartes de normales.
# À relancer si vous ajoutez des textures dans assets/textures ou assets/gen.
$root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -Recurse "$root\assets\textures" -Filter *.import) + @(Get-ChildItem "$root\assets\gen" -Filter *.import)
foreach ($f in $files) {
    $c = Get-Content $f.FullName -Raw
    $c = $c -replace 'compress/mode=\d', 'compress/mode=2'
    $c = $c -replace 'mipmaps/generate=false', 'mipmaps/generate=true'
    $c = $c -replace 'detect_3d/compress_to=\d', 'detect_3d/compress_to=0'
    if ($f.Name -like '*_nor.jpg.import' -or $f.Name -like '*_nrm.png.import') { $c = $c -replace 'compress/normal_map=\d', 'compress/normal_map=1' }
    if ($f.DirectoryName -like '*assets\gen') { $c = $c -replace 'compress/high_quality=false', 'compress/high_quality=true' }
    Set-Content -Path $f.FullName -Value $c -NoNewline -Encoding utf8
}
Write-Output "patched $($files.Count) import files"

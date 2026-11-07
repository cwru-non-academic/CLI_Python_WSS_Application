# Parent-owned baseline protection. Never load this code from selected test sources.
function Assert-BaselineRegularPath([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while($null -ne $item){
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Trusted baseline contains a redirected/reparse path.'}
        $parent=[IO.Path]::GetDirectoryName($item.FullName)
        if(!$parent -or [StringComparer]::Ordinal.Equals($parent,$item.FullName)){break}
        $item=Get-Item -LiteralPath $parent -Force -ErrorAction Stop
    }
}
function Get-TrustedBaselineInventory([string[]]$Roots) {
    $entries=[Collections.Generic.List[string]]::new()
    foreach($root in $Roots){
        $root=[IO.Path]::GetFullPath($root)
        Assert-BaselineRegularPath $root
        if(!(Get-Item -LiteralPath $root -Force).PSIsContainer){
            $hash=(Get-FileHash -LiteralPath $root -Algorithm SHA256 -ErrorAction Stop).Hash
            $entries.Add("$root|ROOT-F|$hash");continue
        }
        $entries.Add("$root|ROOT-D")
        $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($root)
        while($queue.Count){
            $directory=$queue.Dequeue()
            foreach($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop){
                if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Trusted baseline contains a redirected/reparse path.'}
                $relative=[IO.Path]::GetRelativePath($root,$item.FullName).Replace('\','/')
                if($item.PSIsContainer){$entries.Add("$root|D|$relative");$queue.Enqueue($item.FullName)}
                else{$hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash;$entries.Add("$root|F|$relative|$hash")}
            }
        }
    }
    $ordered=$entries.ToArray()
    [Array]::Sort($ordered,[StringComparer]::Ordinal)
    $ordered
}
function New-TrustedBaselineSnapshot([string[]]$Roots) {
    if(!$Roots -or $Roots.Count -eq 0){throw 'At least one protected baseline or authority path is required.'}
    @{roots=@($Roots | ForEach-Object {[IO.Path]::GetFullPath($_)});inventory=@(Get-TrustedBaselineInventory $Roots)}
}
function Assert-TrustedBaselineSnapshot($Snapshot) {
    $current=@(Get-TrustedBaselineInventory $Snapshot.roots)
    if($current.Count -ne $Snapshot.inventory.Count){throw 'Selected suite changed trusted baseline inventory/content.'}
    for($i=0;$i -lt $current.Count;$i++){if(![StringComparer]::Ordinal.Equals($current[$i],$Snapshot.inventory[$i])){throw 'Selected suite changed trusted baseline inventory/content.'}}
}

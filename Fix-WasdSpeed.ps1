#Requires -Version 5.1
<#
.SYNOPSIS
    Fix sluggish / laggy WASD movement in GameLoop (TxGameAssistant / Tencent Gaming
    Buddy), for both the 32-bit and the 64-bit engine, at any resolution.

.DESCRIPTION
    In GameLoop, WASD is emulated as a "CrossKey": the four keys are translated into a
    virtual touch drag on the game's on-screen joystick.

    By default GameLoop puts a finger down on the joystick and then ANIMATES the drag
    outward to the target direction. Every time you change direction (W -> D, or
    A+W -> S+D) the virtual finger slides the long way round the circle
    (NW -> N -> NE -> E -> SE) before it arrives. In a shooter that reads as a sluggish,
    "floaty" character that keeps drifting the old way for a moment.

    The lever for this is the CrossKey's speed= attribute: how fast the virtual finger
    travels from the joystick centre to the target position. GameLoop ships keymaps with
    speed="0" - as slow as it can be. speed="100" makes the finger arrive at the target
    immediately, so direction changes are immediate too.

    This script sets speed="100" on every WASD CrossKey it finds:

      * in every KeyMapMode, so every resolution you have is covered
        (ModeID 1 Normal 720P, 2 Smart 720P, 3 Smart 1080P, 4 Smart 2K, ...)
      * for every game in the config file
      * in every TVM_<id>.xml it finds, so any VM / profile you play on is covered
      * on both the 32-bit and the 64-bit GameLoop engine

    YOUR OFFSET IS LEFT EXACTLY AS IT IS. Offset records where you dragged the joystick
    to, and GameLoop already stores that correctly. There is nothing here to fix, and
    nothing to tune.

    It also CLEARS FlashArrive, if your file has it. FlashArrive="1" is an undocumented
    flag that circulates in tutorials as the fix for this exact problem. It does make the
    joystick arrive instantly - but it does so by moving the point where the finger first
    touches the screen from the joystick's CENTRE out to centre + Offset. The game then
    never sees a touch-down inside the joystick, so it never captures the pointer; the
    touch lands on whatever widget is at that spot (the lean/peek buttons just above the
    joystick, the camera area), and the joystick never recentres. The symptoms are touches
    landing on the wrong button, the character spinning or walking off on its own, and
    single keys feeling dead while two keys together sort of work.

    speed="100" gives you the same instant arrival without any of that, because the finger
    still starts inside the joystick. So this script undoes FlashArrive.
    (Use -KeepFlashArrive if you want it left alone.)

    Everything is done as a byte-safe, text-level edit:
      * the file is read and written as UTF-8 WITHOUT BOM (GameLoop writes it that way)
      * Chinese and other non-ASCII text in Description= attributes is preserved exactly
      * line endings are untouched
      * a timestamped backup is written before anything is changed
      * the result is verified by splicing the ORIGINAL tags back into the modified text
        and comparing it character-for-character with the original - so a change anywhere
        outside the WASD tags aborts the write
      * the file is read back from disk and compared byte-for-byte after writing

.PARAMETER Speed
    How fast the virtual finger travels from the joystick centre to the target position.
    0 = the GameLoop default (slow, animated). 100 = instant. Default: 100.

.PARAMETER Offset
    Advanced. Distance from the joystick centre at which the virtual finger ends up,
    as a fraction of the screen's smaller side.

    Normally you should NOT pass this. Your file's own Offset is the position you dragged
    the joystick to, and it is already right. This script leaves it alone unless you ask
    for a specific value here.

    (If you do pass it, note that GameLoop does not normalise the direction: one key alone
    gives a deflection of Offset, two keys together give about Offset x 1.41.)

.PARAMETER KeepFlashArrive
    Leave an existing FlashArrive attribute alone instead of clearing it. Not recommended -
    see the note about FlashArrive in the description.

.PARAMETER App
    Only touch these game package names, e.g. -App com.tencent.ig,com.tencent.igfit
    Default: every game in the file that has a WASD CrossKey.

.PARAMETER VmId
    Only touch these GameLoop VM ids, e.g. -VmId 100
    Default: every TVM_<id>.xml found.

.PARAMETER ConfigDir
    Use this folder instead of auto-detecting. For a non-standard install.

.PARAMETER List
    Just show which config files were found, then exit. Changes nothing.

.PARAMETER Diagnose
    Report the current state of every WASD CrossKey, per game and per file. Changes nothing.

.PARAMETER Restore
    Restore the newest backup created by this script.

.PARAMETER DryRun
    Show exactly what would change (old tag -> new tag) but write nothing.

.PARAMETER Yes
    Do not ask for confirmation.

.PARAMETER Force
    Skip the "GameLoop is still running" guard. NOT recommended - GameLoop will very
    likely overwrite your change when the emulator shuts down.

.EXAMPLE
    .\Fix-WasdSpeed.ps1 -Diagnose
    Show what every WASD entry currently looks like. Nothing is changed.

.EXAMPLE
    .\Fix-WasdSpeed.ps1 -DryRun
    Preview the change.

.EXAMPLE
    .\Fix-WasdSpeed.ps1
    Apply the fix. This is the recommended way to run it.

.EXAMPLE
    .\Fix-WasdSpeed.ps1 -List
    Show which config files were found.

.EXAMPLE
    .\Fix-WasdSpeed.ps1 -App com.tencent.ig
    Only touch PUBG Mobile, leave every other game alone.

.EXAMPLE
    .\Fix-WasdSpeed.ps1 -VmId 100
    Only touch the VM with id 100.

.EXAMPLE
    .\Fix-WasdSpeed.ps1 -Speed 60
    A softer arrival instead of instant.

.EXAMPLE
    .\Fix-WasdSpeed.ps1 -Restore
    Undo - restore the newest backup.

.NOTES
    Not affiliated with Tencent or GameLoop. Use at your own risk. Your config file is
    backed up before every change, and -Restore always puts it back.
#>
[CmdletBinding()]
param(
    [int]      $Speed = 100,
    [double]   $Offset = 0,
    [switch]   $KeepFlashArrive,
    [string[]] $App,
    [int[]]    $VmId,
    [string]   $ConfigDir,
    [switch]   $List,
    [switch]   $Diagnose,
    [switch]   $Restore,
    [switch]   $DryRun,
    [switch]   $Yes,
    [switch]   $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# GameLoop writes this file as UTF-8 without a BOM. Never change that - adding a BOM or
# re-encoding it can break its parser.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$BackupTag = 'wasd-speed-fix'

# Processes that mean "an Android VM is actually booted". While one of these is alive
# GameLoop owns TVM_<id>.xml and rewrites it when the VM shuts down.
$VmProcesses = @('AndroidEmulatorEn', 'AndroidEmulator', 'AndroidEmulatorEx', 'aow_exe')

# A WASD entry is a <KeyMappingEx ...> or <KeyMapping ...> whose Type is "CrossKey".
# [^>]* never crosses a '>' so the match stays inside one tag even if attributes wrap.
$CrossKeyRx = [regex]'<KeyMapping(?:Ex)?\b[^>]*\bType="CrossKey"[^>]*>'

# ------------------------------------------------------------------ output ---

function Write-Head { param([string]$Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Step { param([string]$Text) Write-Host "   $Text" }
function Write-Ok   { param([string]$Text) Write-Host "   [ok]   $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "   [warn] $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Text) Write-Host "   [fail] $Text" -ForegroundColor Red }

# ------------------------------------------------ config file auto-discovery ---

function Get-TvmFolderCandidates {
    <#
        GameLoop keeps its keymapping in %APPDATA%\AndroidTbox\TVM_<id>.xml. The 64-bit
        build uses the SAME file, so a VM-id agnostic search covers both builds and both
        engine flavours. The extra folders are belt and braces for other builds.
    #>
    $c = New-Object System.Collections.Generic.List[string]

    # An explicit -ConfigDir wins outright: we look there and nowhere else. It must not be
    # added to the usual locations, or the script would also touch the real config.
    if ($ConfigDir) {
        $c.Add($ConfigDir)
        return $c
    }

    foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        foreach ($leaf in @('AndroidTbox', 'AndroidTbox64', 'AOW', 'Tencent\AndroidTbox')) {
            $c.Add((Join-Path $root $leaf))
        }
    }
    return $c | Select-Object -Unique
}

function Get-TvmFileList {
    param([int[]]$VmId)

    $found = New-Object System.Collections.Generic.List[object]

    # 1) the well-known locations
    foreach ($dir in (Get-TvmFolderCandidates)) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '^TVM_\d+\.xml$') { $found.Add($f) }
        }
    }

    # 2) fall back to a shallow scan, in case a future build moves the folder.
    #    Never when -ConfigDir was given - the caller asked for that folder specifically.
    if ($found.Count -eq 0 -and -not $ConfigDir) {
        foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
            if (-not $root) { continue }
            foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Depth 3 -Force -ErrorAction SilentlyContinue)) {
                if ($f.Name -match '^TVM_\d+\.xml$') { $found.Add($f) }
            }
        }
    }

    # de-duplicate by full path
    $unique = @{}
    foreach ($f in $found) { $unique[$f.FullName] = $f }
    $result = @($unique.Values | Sort-Object FullName)

    if ($VmId -and $VmId.Count -gt 0) {
        $result = @($result | Where-Object {
            $m = [regex]::Match($_.Name, '^TVM_(\d+)\.xml$')
            $VmId -contains [int]$m.Groups[1].Value
        })
    }

    if ($result.Count -eq 0) {
        throw ("No TVM_<id>.xml config file found.`n`n" +
               "Run GameLoop at least once and set up your controls in the game, so it`n" +
               "creates %APPDATA%\AndroidTbox\TVM_<id>.xml. Or point at the folder`n" +
               "directly with:  -ConfigDir `"C:\path\to\AndroidTbox`"")
    }
    return $result
}

function Get-EngineFlavour {
    <#
        GameLoop ships two Android builds: a 32-bit one (x86 guest) and a 64-bit one
        (x86_64 guest). They use different engine components (VDI_<id> / TBOX versus
        VDI_<id>_x64 / TBOX_64) but the SAME keymapping file, so the fix below applies to
        both. This is purely informational.
    #>
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($pf) { $roots.Add((Join-Path $pf 'TxGameAssistant')) }
    }
    $roots.Add('C:\Temp\TxGameDownload\Component')

    $has64 = $false
    $has32 = $false

    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($d in (Get-ChildItem -LiteralPath $r -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($d.Name -match '^VDI_\d+_x64$' -or $d.Name -eq 'TBOX_64') { $has64 = $true }
            elseif ($d.Name -match '^VDI_\d+$' -or $d.Name -eq 'TBOX')  { $has32 = $true }
        }
    }

    if ($has64 -and $has32) { return '32-bit + 64-bit both installed' }
    if ($has64)             { return '64-bit (x86_64 Android guest)' }
    if ($has32)             { return '32-bit (x86 Android guest)' }
    return 'unknown'
}

function Assert-GameLoopClosed {
    if ($Force) { Write-Warn 'Force set - skipping the GameLoop running check.'; return }

    $live = @(Get-Process -ErrorAction SilentlyContinue |
              Where-Object { $VmProcesses -contains $_.ProcessName })

    if ($live.Count -gt 0) {
        $names = ($live | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        throw ("GameLoop's emulator is still running ($names).`n`n" +
               "Close GameLoop completely - including the tray icon - then run this again.`n" +
               "If you edit the file while the VM is alive, GameLoop overwrites your change`n" +
               "when it shuts down.")
    }

    if (Get-Process -Name 'AppMarket' -ErrorAction SilentlyContinue) {
        Write-Warn "GameLoop's launcher (AppMarket.exe) is open. Safer to close it too."
    }
}

# ------------------------------------------------------ reading and writing ---

function Read-TvmText {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    # Strict decode: if a file is ever not valid UTF-8, fail loudly instead of mangling it.
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    return [pscustomobject]@{ Bytes = $bytes; Text = $strict.GetString($bytes) }
}

function Get-ItemRanges {
    <#
        Every <Item ApkName="..."> ... </Item> block, with the exact offsets of both the
        whole block and its body. Items are top-level siblings, so a non-greedy match
        between the opening and the closing tag is exact.
    #>
    param([string]$Text)

    # (?s) = singleline, so '.' also matches newlines - an Item block spans many lines.
    $rx  = [regex]'(?s)<Item\s[^>]*ApkName="(?<apk>[^"]*)"[^>]*>(?<body>.*?)</Item>'
    $out = New-Object System.Collections.Generic.List[object]

    foreach ($m in $rx.Matches($Text)) {
        $body = $m.Groups['body']
        $out.Add([pscustomobject]@{
            ApkName   = $m.Groups['apk'].Value
            Start     = $m.Index
            End       = $m.Index + $m.Length
            BodyStart = $body.Index
            BodyEnd   = $body.Index + $body.Length
        })
    }
    return $out
}

# -------------------------------------------------------- tag manipulation ---

function Get-TagParts {
    param([string]$Tag)
    if ($Tag.EndsWith('/>')) { return [pscustomobject]@{ Body = $Tag.Substring(0, $Tag.Length - 2); Tail = '/>' } }
    if ($Tag.EndsWith('>'))  { return [pscustomobject]@{ Body = $Tag.Substring(0, $Tag.Length - 1); Tail = '>'  } }
    throw "Unexpected tag ending: $Tag"
}

function Set-TagAttribute {
    param([string]$Tag, [string]$Name, [string]$Value)

    # Attributes here are always name="value" with no spaces around '='.
    $pattern = "(?<=\s)" + [regex]::Escape($Name) + '="[^"]*"'

    if ([regex]::IsMatch($Tag, $pattern)) {
        # Literal replacement - escape '$' so it cannot be read as a backreference.
        return [regex]::Replace($Tag, $pattern, ($Name + '="' + $Value.Replace('$', '$$') + '"'), 1)
    }
    # Not present -> append at the end of the attribute list.
    return $Tag + ' ' + $Name + '="' + $Value + '"'
}

function Get-TagAttribute {
    param([string]$Tag, [string]$Name)
    $m = [regex]::Match($Tag, '(?<=\s)' + [regex]::Escape($Name) + '="([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function New-FixedCrossKeyTag {
    <#
        The whole fix, in one tag.

        speed        -> the fix. 100 = the virtual finger arrives instantly.
        Offset       -> untouched unless the caller asked for a specific value.
        FlashArrive  -> cleared, because it relocates the touch-down point out of the
                        joystick and that is what causes stray touches. A tag that does
                        not carry the attribute at all already behaves as "0", so in that
                        case nothing is added.
    #>
    param(
        [string]$Tag,
        [int]$Speed,
        [double]$Offset,           # 0 = leave the existing Offset alone
        [switch]$KeepFlashArrive
    )

    $parts = Get-TagParts -Tag $Tag
    $body  = $parts.Body

    $body = Set-TagAttribute -Tag $body -Name 'speed' -Value "$Speed"

    if ($Offset -gt 0) {
        # InvariantCulture, so a machine that uses ',' as the decimal separator does not
        # write Offset="0,035" and corrupt the value.
        $offsetText = $Offset.ToString('0.000000', [Globalization.CultureInfo]::InvariantCulture)
        $body = Set-TagAttribute -Tag $body -Name 'Offset' -Value $offsetText
    }

    if (-not $KeepFlashArrive -and (Get-TagAttribute -Tag $body -Name 'FlashArrive') -ne '') {
        $body = Set-TagAttribute -Tag $body -Name 'FlashArrive' -Value '0'
    }

    return $body + $parts.Tail
}

# ---------------------------------------------------------- the core edit ---

function Invoke-CrossKeyFix {
    <#
        Rewrite every selected WASD CrossKey in the whole file text in one pass.

        Returns $null when there is nothing to change - either no CrossKey matched, or
        every one of them is already exactly as it should be.

        Otherwise returns Text + Changes. Each change records the tag that was replaced,
        the tag that replaced it, and where the new tag starts - which is what makes an
        exact round-trip verification possible.
    #>
    param(
        [string]   $Text,
        [object[]] $Items,
        [object]   $Allowed,      # $null = allow all, else hashtable of ApkName -> $true
        [int]      $Speed,
        [double]   $Offset,
        [switch]   $KeepFlashArrive
    )

    $selected = New-Object System.Collections.Generic.List[object]

    foreach ($m in $CrossKeyRx.Matches($Text)) {
        $owner = $null
        foreach ($it in $Items) {
            if ($m.Index -ge $it.BodyStart -and $m.Index -lt $it.BodyEnd) { $owner = $it; break }
        }
        if ($null -eq $owner) { continue }
        if ($Allowed -and -not $Allowed.ContainsKey($owner.ApkName)) { continue }
        $selected.Add([pscustomobject]@{ Match = $m; Item = $owner })
    }

    if ($selected.Count -eq 0) { return $null }

    $sb      = New-Object System.Text.StringBuilder
    $last    = 0
    $outLen  = 0
    $changes = New-Object System.Collections.Generic.List[object]

    foreach ($s in $selected) {
        $m = $s.Match

        $newTag = New-FixedCrossKeyTag -Tag $m.Value -Speed $Speed -Offset $Offset `
                                       -KeepFlashArrive:$KeepFlashArrive

        # Already correct -> leave the bytes alone. This is what makes a second run a
        # no-op instead of a pointless rewrite.
        if ($newTag -ceq $m.Value) { continue }

        $pre = $Text.Substring($last, $m.Index - $last)
        [void]$sb.Append($pre); $outLen += $pre.Length

        $newStart = $outLen
        [void]$sb.Append($newTag); $outLen += $newTag.Length

        $changes.Add([pscustomobject]@{
            ApkName  = $s.Item.ApkName
            OldTag   = $m.Value
            NewTag   = $newTag
            NewStart = $newStart
        })

        $last = $m.Index + $m.Length
    }

    if ($changes.Count -eq 0) { return $null }

    [void]$sb.Append($Text.Substring($last))

    # .ToArray() is deliberate: a List<object> stored as a property value stays a List
    # (only a function's return value gets unwrapped), and applying @() to it later trips
    # a PowerShell binder bug ("Argument types do not match").
    return [pscustomobject]@{ Text = $sb.ToString(); Changes = $changes.ToArray() }
}

function Test-RoundTrip {
    <#
        The strongest check available: splice the ORIGINAL tags back into the modified
        text at exactly the positions their replacements occupy. If the result is
        character-for-character identical to the original, then nothing outside the
        WASD tags was touched - not by a single character.
    #>
    param([string]$Original, [string]$Modified, [object[]]$Changes)

    $rev = New-Object System.Text.StringBuilder
    $pos = 0
    foreach ($c in $Changes) {
        [void]$rev.Append($Modified.Substring($pos, $c.NewStart - $pos))
        [void]$rev.Append($c.OldTag)
        $pos = $c.NewStart + $c.NewTag.Length
    }
    [void]$rev.Append($Modified.Substring($pos))

    return ($rev.ToString() -ceq $Original)
}

# ----------------------------------------------------------- backup / undo ---

function Get-BackupList {
    param([string]$Path)
    $dir  = Split-Path -Parent $Path
    $base = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext  = [IO.Path]::GetExtension($Path)
    return @(Get-ChildItem -LiteralPath $dir -File -Filter "$base`_backup_$BackupTag`_*$ext" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending)
}

function New-Backup {
    param([string]$Path)
    $dir   = Split-Path -Parent $Path
    $base  = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext   = [IO.Path]::GetExtension($Path)
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $dest  = Join-Path $dir "$base`_backup_$BackupTag`_$stamp$ext"
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    return $dest
}

# ------------------------------------------------------------------ report ---

function Get-CrossKeyInfo {
    param([string]$Tag)
    $speed = Get-TagAttribute -Tag $Tag -Name 'speed'
    $off   = Get-TagAttribute -Tag $Tag -Name 'Offset'
    $flash = Get-TagAttribute -Tag $Tag -Name 'FlashArrive'
    if ($speed -eq '') { $speed = '-' }
    if ($off   -eq '') { $off   = '-' }
    if ($flash -eq '') { $flash = '-' }
    # "fixed" = the finger arrives instantly, and nothing is dragging the touch-down
    # point out of the joystick.
    $ok = ($speed -ne '0' -and $speed -ne '-') -and ($flash -ne '1')

    # GameLoop derives Offset from where you dragged the joystick, so the values it writes
    # are uneven (0.070258, 0.057878...). A round value can only have been typed in by
    # hand - almost always by an older tutorial, together with FlashArrive="1". Worth
    # flagging, because that value is now the only thing setting how far the stick moves.
    $edited = ($off -match '^\d+\.\d*0{3}$')

    return [pscustomobject]@{ Speed = $speed; Offset = $off; Flash = $flash; Fixed = $ok; LooksEdited = $edited }
}

# ============================================================ main ==========

Write-Host ''
Write-Host '  GameLoop - WASD speed fix' -ForegroundColor White
Write-Host '  Makes WASD direction changes instant instead of sluggish.'
Write-Host '  (any resolution, any game, both the 32-bit and 64-bit engine)'

$files = Get-TvmFileList -VmId $VmId

if ($List) {
    Write-Head 'Config files found'
    Write-Step "GameLoop engine: $(Get-EngineFlavour)"
    foreach ($f in $files) { Write-Step "$($f.FullName)   ($([math]::Round($f.Length/1KB,1)) KB)" }
    Write-Host ''
    return
}

if ($Restore) {
    Write-Head 'Restore'
    Assert-GameLoopClosed
    $did = $false
    foreach ($f in $files) {
        $list = Get-BackupList -Path $f.FullName
        if ($list.Count -eq 0) { Write-Step "$($f.Name): no backup found."; continue }
        $newest = $list[0]
        if (-not $Yes) {
            $ans = Read-Host "   Restore $($f.Name) from $($newest.Name)? [y/N]"
            if ($ans -notmatch '^(y|yes)$') { Write-Step 'skipped.'; continue }
        }
        Copy-Item -LiteralPath $newest.FullName -Destination $f.FullName -Force
        Write-Ok "$($f.Name) restored from $($newest.Name)"
        $did = $true
    }
    if (-not $did) { Write-Warn 'Nothing was restored.' }
    Write-Host ''
    return
}

Write-Head 'Config files'
Write-Step "GameLoop engine: $(Get-EngineFlavour)"
foreach ($f in $files) { Write-Step "$($f.FullName)   ($([math]::Round($f.Length/1KB,1)) KB)" }

$loaded = @{}
foreach ($f in $files) { $loaded[$f.FullName] = (Read-TvmText -Path $f.FullName) }

# --------------------------------------------------------- diagnose mode ---

if ($Diagnose) {
    $total   = 0
    $notOk   = 0
    $edited  = 0
    foreach ($f in $files) {
        # Full path: two VMs (or a VM and a -ConfigDir copy) can share the file name.
        Write-Head $f.FullName
        $txt     = $loaded[$f.FullName].Text
        $items   = Get-ItemRanges -Text $txt
        $allHits = @($CrossKeyRx.Matches($txt))
        foreach ($it in $items) {
            $hits = @($allHits | Where-Object {
                $_.Index -ge $it.BodyStart -and $_.Index -lt $it.BodyEnd
            })
            if ($hits.Count -eq 0) { continue }
            $total += $hits.Count
            Write-Step "app: $($it.ApkName)"
            foreach ($h in $hits) {
                $i = Get-CrossKeyInfo -Tag $h.Value
                if (-not $i.Fixed) { $notOk++ }
                if ($i.LooksEdited) { $edited++ }
                $mark = if ($i.Fixed) { '[ok] ' } else { '[--] ' }
                $note = if ($i.LooksEdited) { '   <- Offset looks hand-typed' } else { '' }
                Write-Step "      $mark speed=$($i.Speed)  Offset=$($i.Offset)  FlashArrive=$($i.Flash)$note"
            }
        }
    }
    Write-Host ''
    Write-Step "Total WASD entries: $total"
    if ($notOk -eq 0) {
        Write-Step 'All of them are already fixed. Nothing to do.'
    } else {
        Write-Step "$notOk still need fixing. Run this script without -Diagnose to apply."
    }
    Write-Step '([ok] = speed is set and FlashArrive is not dragging the touch out of the joystick)'

    if ($edited -gt 0) {
        Write-Host ''
        Write-Warn "$edited of them have an Offset that looks hand-typed."
        Write-Step 'GameLoop writes uneven values (0.070258, 0.057878); a round one like'
        Write-Step '0.035000 comes from a tutorial. If you followed an older guide, that'
        Write-Step 'value is now the only thing setting how far the stick moves - so the'
        Write-Step 'character may walk slowly. Fix it by dragging the joystick to where you'
        Write-Step 'want it in GameLoop while the game is running, or restore a backup of'
        Write-Step 'your config from before you ran that guide.'
    }
    Write-Host ''
    return
}

# ----------------------------------------------------------- plan the fix ---

if ($App -and $App.Count -gt 0) {
    $allowed = @{}
    foreach ($a in $App) { if ($a.Trim()) { $allowed[$a.Trim()] = $true } }
} else {
    $allowed = $null
}

$plans = New-Object System.Collections.Generic.List[object]
foreach ($f in $files) {
    $txt   = $loaded[$f.FullName].Text
    $items = Get-ItemRanges -Text $txt
    $r     = Invoke-CrossKeyFix -Text $txt -Items $items -Allowed $allowed -Speed $Speed -Offset $Offset `
                                -KeepFlashArrive:$KeepFlashArrive
    if ($null -eq $r) { continue }
    $plans.Add([pscustomobject]@{ File = $f; Original = $txt; Result = $r })
}

if ($plans.Count -eq 0) {
    Write-Host ''
    Write-Step 'Every WASD entry is already correct - nothing to do.'
    Write-Step 'Run with -Diagnose to see the current state.'
    Write-Host ''
    return
}

$totalChanges = ($plans | ForEach-Object { $_.Result.Changes.Count } | Measure-Object -Sum).Sum

Write-Head 'Plan'
Write-Step "speed       : $Speed$(if ($Speed -eq 100) { '  (instant)' })"
Write-Step "Offset      : $(if ($Offset -gt 0) { "$Offset  (overridden)" } else { 'left exactly as it is' })"
Write-Step "FlashArrive : $(if ($KeepFlashArrive) { 'left as it is' } else { 'cleared (use -KeepFlashArrive to leave it)' })"
Write-Host ''
foreach ($p in $plans) {
    $perApp = $p.Result.Changes | Group-Object ApkName
    Write-Step $p.File.FullName
    foreach ($g in $perApp) {
        Write-Step "     $($g.Name)  -  $($g.Count) WASD entr$(if ($g.Count -eq 1) {'y'} else {'ies'})"
    }
}
Write-Step "Total: $totalChanges"

# ------------------------------------------------------------ dry run ---

if ($DryRun) {
    Write-Head 'Dry run (nothing written)'
    foreach ($p in $plans) {
        foreach ($c in $p.Result.Changes) {
            Write-Host ''
            Write-Host "   [$($c.ApkName)]" -ForegroundColor DarkGray
            Write-Host '   - ' -ForegroundColor DarkGray -NoNewline; Write-Host $c.OldTag -ForegroundColor DarkGray
            Write-Host '   + ' -ForegroundColor Green    -NoNewline; Write-Host $c.NewTag -ForegroundColor Green
        }
    }
    Write-Host ''
    return
}

if (-not $Yes) {
    Write-Host ''
    $ans = Read-Host "   Apply to $totalChanges WASD entr$(if ($totalChanges -eq 1) {'y'} else {'ies'})? [y/N]"
    if ($ans -notmatch '^(y|yes)$') { Write-Host ''; Write-Step 'Cancelled.'; Write-Host ''; return }
}

# ------------------------------------------------------------- apply ---

Write-Head 'Applying'
Assert-GameLoopClosed

foreach ($p in $plans) {
    $path = $p.File.FullName
    $name = $p.File.Name

    # Verify in memory BEFORE touching the disk.
    if (-not (Test-RoundTrip -Original $p.Original -Modified $p.Result.Text -Changes $p.Result.Changes)) {
        throw "Round-trip verification failed for $name - nothing was written."
    }
    Write-Step "$name : round-trip verified"

    $backup = New-Backup -Path $path
    Write-Step "$name : backup -> $(Split-Path -Leaf $backup)"

    $expectedBytes = $Utf8NoBom.GetBytes($p.Result.Text)
    [IO.File]::WriteAllBytes($path, $expectedBytes)

    # Read back from disk and confirm byte-for-byte that what landed is what we built.
    $after = [IO.File]::ReadAllBytes($path)
    $same  = ($after.Length -eq $expectedBytes.Length)
    if ($same) {
        for ($i = 0; $i -lt $after.Length; $i++) {
            if ($after[$i] -ne $expectedBytes[$i]) { $same = $false; break }
        }
    }
    if (-not $same) {
        Write-Bad "$name : read-back mismatch! Restoring backup."
        Copy-Item -LiteralPath $backup -Destination $path -Force
        throw "Write verification failed for $name - the backup was restored."
    }

    Write-Ok "$name : written and verified ($($after.Length) bytes, $($p.Result.Changes.Count) entries)"
}

Write-Head 'Done'
Write-Step 'Open GameLoop and test: WASD direction changes should be instant now.'
Write-Step 'To undo everything:  -Restore'
Write-Host ''

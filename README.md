# GameLoop WASD Speed Fix

**Makes WASD direction changes instant in GameLoop instead of sluggish.**

One click. No install. No tuning. Works for every resolution, every game, and both the
32-bit and 64-bit GameLoop engine.

```
Before:  W . . . . . . . . . . . . D          you press D, the character keeps
         ^                             ^      walking north for a moment first

After:   W D                                  you press D, the character turns now
```

---

## The problem

GameLoop does not send key presses to the game. It emulates your WASD as a **virtual
touch drag on the game's on-screen joystick** — an internal mapping type called a
`CrossKey`.

That mapping has a hidden `speed` value, and **GameLoop ships it at `speed="0"`** — as slow
as it goes. So instead of the virtual finger appearing at the target direction, it starts
at the joystick's **centre** and *animates* its way outward, sweeping around the circle:

```
        N
    NW      NE          press A+W  ->  slide draws NW -> N -> NE -> E ...
   W    +    E
    SW      SE          press S+D  ->  slide draws SE -> S -> SW -> W ...
        S
```

In a shooter this reads as a "floaty", laggy character that keeps drifting the old way for
a moment after you change direction. Turning a corner feels like steering a boat.

## The fix

**Set `speed="100"`** on the CrossKey — the virtual finger arrives at the target
immediately, so direction changes are immediate.

That is the whole fix. It is one attribute.

---

## The trap: `FlashArrive`

If you searched for this problem before, you probably found a tutorial telling you to set
`FlashArrive="1"`. **Do not do that.** It is the reason so many people end up with
*new* problems after "fixing" the sluggishness.

`FlashArrive="1"` does make the joystick arrive instantly — but it does it the wrong way.
Instead of moving the finger faster, it **moves where your finger first touches the
screen**. The touch no longer starts inside the joystick; it starts directly at the
target position:

```
speed="100" only                    FlashArrive="1"
                                    
   +--joystick--+                     +--joystick--+
   |            |                     |            |
   |     x ON   |  <- touch-down      |      .     |
   |            |     INSIDE         |            |      x ON  <- touch-down OUTSIDE
   +------------+                     +------------+         (on a peek button!)

   game captures the joystick         game never sees your touch land on the joystick,
   on touch-down. Everything after    so it never captures the pointer. The tap goes
   that is a normal drag.             to whatever widget is there.
```

The symptoms people report from this, and blame on the game:

* touches landing on the **peek / lean buttons** above the joystick
* the **camera or aim** drifting on its own
* the joystick **not recentring** when they let go
* a **single key doing nothing** while two keys together sort of work
* the character walking off in a **random direction**

If you already did this, don't worry — running this script **clears `FlashArrive` for
you**, and you get the instant movement without any of it. (Use `-KeepFlashArrive` if you
genuinely want it left alone.)

---

## Your Offset is not touched

You may also have read that you need to change `Offset`. **You don't.**

`Offset` records how far from the joystick centre the finger ends up — which is really
just *where you dragged the joystick to*. GameLoop writes it for you when you position the
joystick in its UI, and it is already correct. Every guide that tells you to type a number
in there is guessing at a value that depends on your resolution, your HUD layout and your
joystick size.

So this script **leaves your `Offset` exactly as it is.** There is nothing to tune.

> If you *did* follow one of those guides and typed a round number like `0.035000` into
> `Offset`, `-Diagnose` will flag it for you — see [Diagnose](#show-me-the-current-state).

---

## Requirements

* Windows 10 or 11
* GameLoop installed, and **launched at least once** so it has created its config file
* Windows PowerShell 5.1 (built into Windows — nothing to install)

No Python. No Node. No dependencies.

---

## Quick start

1. **Close GameLoop completely** — including the tray icon. The file is rewritten when the
   emulator shuts down, so an edit made while it is running is lost.
2. Double-click **`run.bat`**.
3. Press **`2`** to apply the fix.
4. Done. Open GameLoop and play.

If you want to look before you leap, press **`1`** first (shows the current state, changes
nothing) or **`3`** (previews the exact edit).

### Other menu options

| Key | What it does |
| --- | --- |
| `1` | Show the current state of every WASD mapping. Changes nothing. |
| `2` | Apply the fix. |
| `3` | Preview the exact before/after edit. Changes nothing. |
| `4` | Show which config files were found. |
| `5` | Fix only one game, by package name. |
| `6` | Undo — restore the newest backup. |

---

## Command line

```powershell
.\Fix-WasdSpeed.ps1                  # apply the fix
.\Fix-WasdSpeed.ps1 -Diagnose        # show current state, change nothing
.\Fix-WasdSpeed.ps1 -DryRun          # preview the edit, write nothing
.\Fix-WasdSpeed.ps1 -List            # which config files were found
.\Fix-WasdSpeed.ps1 -Restore         # undo
```

More options:

| Option | Default | Meaning |
| --- | --- | --- |
| `-Speed <int>` | `100` | `100` = instant. `0` = GameLoop's slow default. Lower values give a softer arrival. |
| `-App <names>` | all games | Only touch these package names, e.g. `-App com.tencent.ig` |
| `-VmId <ids>` | all VMs | Only touch these GameLoop VM ids, e.g. `-VmId 100` |
| `-ConfigDir <path>` | auto | Look in this folder, and only this folder |
| `-Offset <value>` | *unset* | Advanced. Force a specific Offset instead of keeping yours. |
| `-KeepFlashArrive` | off | Leave an existing `FlashArrive` alone instead of clearing it |
| `-Yes` | off | Skip the confirmation prompt |
| `-Force` | off | Skip the "GameLoop is running" guard. Not recommended. |

Examples:

```powershell
# just PUBG Mobile
.\Fix-WasdSpeed.ps1 -App com.tencent.ig

# a softer arrival instead of instant
.\Fix-WasdSpeed.ps1 -Speed 60

# see exactly what would change, per game and per resolution
.\Fix-WasdSpeed.ps1 -DryRun
```

---

## Show me the current state

```powershell
.\Fix-WasdSpeed.ps1 -Diagnose
```

```
== C:\Users\you\AppData\Roaming\AndroidTbox\TVM_100.xml
   app: com.tencent.ig
         [--]  speed=0    Offset=0.070258  FlashArrive=-
         [--]  speed=100  Offset=0.035000  FlashArrive=1   <- Offset looks hand-typed
         ...
   Total WASD entries: 8
   8 still need fixing. Run this script without -Diagnose to apply.
```

`[ok]` means that mapping is already correct. `[--]` means it is not.

The `<- Offset looks hand-typed` note means the value is a round number, which GameLoop
never writes itself — so it came from a tutorial. Once the script clears `FlashArrive`,
that value becomes the only thing setting how far the stick moves, so movement may feel
*slow* rather than broken. The fix is to drag the joystick where you want it in GameLoop
while a game is running, or to restore a backup of your config from before you followed
that guide.

---

## What it covers

Nothing is hard-coded to one setup:

| | |
| --- | --- |
| **Every resolution** | Fixes every `KeyMapMode` in the file — Normal 720P, Smart 720P, Smart 1080P, Smart 2K, and anything else you have. Not just the one in use. |
| **Every game** | Fixes every game in the config file that has a WASD mapping. PUBG Mobile, PUBG Mobile Flash, Free Fire — anything. |
| **Every profile** | Fixes every `TVM_<id>.xml` it finds, so any VM / profile you play on is covered. |
| **Both engine builds** | The 32-bit and the 64-bit GameLoop engines share the same keymapping file, so one run covers both. The script tells you which you have. |
| **Any key layout** | It targets the mapping *type* (`CrossKey`), not the specific keys — so it works even if you rebound WASD. |

---

## Safety

Your config file is the only thing it touches, and it is treated carefully.

**Before writing**

* GameLoop's emulator must be closed (it refuses otherwise — `-Force` overrides).
* A timestamped backup is written next to your config:
  `TVM_100_backup_wasd-speed-fix_2026-10-03_012515.xml`
* The edit is computed **in memory first**, and verified by splicing the original tags back
  into the modified text and comparing it **character-for-character** with the original
  file. If anything outside the WASD tags moved by even one character, nothing is written.

**After writing**

* The file is read back from disk and compared **byte-for-byte** with what was built.
* If it does not match, the backup is restored automatically and the script stops.

**What it deliberately does not do**

* No BOM. GameLoop writes UTF-8 without one, and the script keeps it that way.
* No re-serialising through an XML parser. The file isn't valid XML as written (it has no
  root element), and re-encoding it would reformat 280 KB and mangle the Chinese text in
  the button names. Everything is a surgical text-level edit.
* No touching of line endings, other games' settings, or the button list.
* Running it twice does nothing the second time — it detects that every mapping is
  already correct and exits without writing.

---

## Undo

```powershell
.\Fix-WasdSpeed.ps1 -Restore
```

or press **`6`** in `run.bat`. This restores the newest backup.

Your backups are ordinary files sat next to the config:

```
%APPDATA%\AndroidTbox\TVM_100_backup_wasd-speed-fix_<date>_<time>.xml
```

---

## FAQ

**Is this a cheat / will I get banned?**
No. It changes how *your own input* is translated on your own machine — same category as
changing your mouse DPI or rebinding a key. It gives you no information the game does not
already give you, and it touches nothing but GameLoop's local config file.

**Does it work for games other than PUBG?**
Yes, any game where you use WASD. Free Fire, Call of Duty Mobile, whatever. GameLoop maps
all of them through the same `CrossKey` type.

**GameLoop updated and the sluggishness came back.**
A GameLoop update can rewrite the config. Just run it again.

**I moved my joystick and now movement feels weak.**
Fine — your `Offset` is your own and the script never touches it. Move the joystick in
GameLoop's UI and it updates itself.

**I used the `FlashArrive` trick before. Anything I should do?**
Just run this script. It clears `FlashArrive` for you. If you *also* edited `Offset` by
hand, see the note in [Diagnose](#show-me-the-current-state).

**Will this make my aim different?**
No. It only affects the WASD movement mapping. Your mouse/aim mapping is untouched.

**What is the risk?**
If your config were somehow corrupted you would lose your button layout — which is why the
script makes a backup before every write, verifies the edit character-for-character before
writing, verifies the bytes on disk after writing, and can restore itself automatically.

---

## Roman Urdu

**Masla:** GameLoop WASD ko seedha game tak nahi bhejta — woh tumhare WASD ko on-screen
joystick par **virtual touch drag** bana kar bhejta hai. Us mapping mein ek chhupi hui
`speed` value hoti hai, aur GameLoop use **`speed="0"`** par ship karta hai (yaani sab se
slow). Is liye virtual ungli joystick ke **centre** se shuru ho kar target tak *animate*
karti hui jati hai — poora chakkar kat kar. Isi wajah se character "floaty" lagta hai aur
direction badalne par thori der purani taraf chalta rehta hai.

**Fix:** us CrossKey par **`speed="100"`** kar do. Bas. Virtual ungli turant target par
pahunch jati hai, direction change foran ho jata hai.

**Trap:** internet par jo tutorials `FlashArrive="1"` likhne ko kehte hain, **woh nuqsan
karta hai**. Woh arrival to instant kar deta hai, magar tareeqa ghalat hai — woh ungli ki
**starting jagah** ko joystick ke centre se hata kar seedha target par le jata hai. Phir
game ko kabhi pata hi nahi chalta ke touch joystick par land hua, woh joystick ka pointer
capture nahi karta, aur touch uske aas paas wale button (peek/lean, camera) par chala jata
hai. Iske symptoms: ghalat button dabna, joystick ka recentre na hona, **akeley key ka
jawab na dena aur do keys milane par ajeeb chalna**, character ka khud hi kisi taraf chal
dena. Yeh script `FlashArrive` ko **saaf kar deti hai**.

**Offset ko haath mat lagao.** Woh batata hai ke tumne joystick kahan rakha hai — GameLoop
khud usay likhta hai jab tum UI mein joystick drag karte ho, aur woh pehle se sahi hota
hai. Is script mein **Offset ko waisa hi chhoda jata hai**, koi tuning nahi chahiye.

**Chalane ka tareeqa:** GameLoop **poora band** karo (tray icon bhi), phir **`run.bat`**
par double-click karo, aur **`2`** dabao. Bas.

**Wapas purana karna ho:** option **`6`** (ya `-Restore`). Yeh sab se naya backup wapas
laga deta hai.

**Ye sab resolutions, sab games, aur 32-bit/64-bit dono par kaam karta hai** — file ke
saare `KeyMapMode` block fix hote hain, sirf chalu wala nahi.

---

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Tencent, GameLoop, or TxGameAssistant. Use at your own risk.

---

## Related

* The keymapping side of the same problem — copying a whole button layout from one game
  build to another — lives in
  [pubgm-flash-keymapping-gameloop](https://github.com/Ahsuu27488/pubgm-flash-keymapping-gameloop).

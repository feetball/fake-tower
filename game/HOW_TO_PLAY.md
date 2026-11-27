# Fake Tower: How to Play

Two voices on the radio both say they are the tower. One is real. One wants you dead.

This is the player manual. Every key and number here was checked against the game code. If a key is not listed, the game does not have it.

Contents

1. [The game in one minute](#1-the-game-in-one-minute)
2. [Getting a game going](#2-getting-a-game-going)
3. [The radio](#3-the-radio)
4. [Pilot guide](#4-pilot-guide)
5. [Controller guide](#5-controller-guide)
6. [Spotting the impostor (pilots)](#6-spotting-the-impostor-pilots)
7. [Playing the impostor](#7-playing-the-impostor)
8. [The end screen](#8-the-end-screen)
9. [Reference: the airport](#9-reference-the-airport)
10. [Touch controls (phones and tablets)](#10-touch-controls-phones-and-tablets)

---

## 1. The game in one minute

The airport is KFTW, Fallow Ridge Regional. It has one runway (27) and one approach (ILS 27). It is night, in fog. The weather is the same all round.

Roles are handed out at random when the host starts the round:

| Role | How many | What you do | Who you win with |
| --- | --- | --- | --- |
| Real controller | 1 | You see the radar scope. Talk the pilots down the ILS and keep them apart and clear of terrain. | The pilots |
| Impostor controller | 1 | You see the same scope. You also claim to be the tower. You want aircraft to crash. | Nobody. You win alone. |
| Pilot | 2 to 6 | You fly one aircraft on instruments. You cannot see other traffic. | The real controller |

Everyone knows which two players are controllers. Only the two controllers know which of them is the impostor. Pilots are never told.

**How the round ends.** The round ends when no aircraft is still flying. The tower side (real controller and all pilots) wins if **strictly more than half** of the aircraft landed. Otherwise the impostor wins. Exactly half is an impostor win.

**What controllers can and cannot do.** Controllers cannot move anyone's aircraft. They only talk, by voice or on the text radio (section 3.2). Pilots fly their own aircraft and decide whom to obey.

**No microphone needed.** Everything said on the frequency can also be sent as a text message from buttons and keys: instructions, readbacks, fuel calls, accusations. Voice and text players can share a game.

---

## 2. Getting a game going

| Menu item | What it does |
| --- | --- |
| **Host Game** | Opens a game on UDP port **27270** and takes you to the lobby. |
| **Join Game** | Opens the address form. Type the host's IP address and the port (27270 unless the host changed it), then Connect. In a browser the form is always open and the port defaults to 27271 (WebSocket). |
| **Solo Practice** | Offline rounds against AI players, which talk on the text radio: **Fly with an AI tower**, **Spot the impostor**, **Be the controller** and **Free flight** (see *Solo practice* below). |
| **How to Play** | The rules and controls overlay. Esc closes it. |
| **Settings** | Volume (**Master**, **Ambient noise**, **Radio / ATC voice**), fullscreen, reading the text radio aloud, leave game, quit. |
| **Quit** | Closes the game. Not shown in a browser or on iPhone/iPad (close the tab or swipe the app away). |

Enter your name first (up to 16 characters). Esc opens Settings at any time, including during a round. **The game does not pause.** The three volume sliders work separately: **Ambient noise** is the flight-deck sound (engines, slipstream, rain, gear and flaps; aural warnings always stay at full volume) and **Radio / ATC voice** is everything on the frequency (voices, static and the text radio read aloud). On a touchscreen, the **MENU** button (top right) opens Settings instead; see section 10.

**Hosting**

1. Choose Host Game. The lobby shows your addresses next to the port.
2. Same network (LAN): give the others the address shown in the lobby.
3. Over the internet: forward **UDP port 27270** on your router to your PC and give the others your public IP. Allow the game through your firewall when asked. Direct IP is the only way to connect for now.
4. The Start Round button works once at least **4 players** are connected. The maximum is 8. The lobby tells you how many are still needed.
5. Roles are assigned at random when you press Start Round. With 4 players you get 2 controllers and 2 pilots. Every extra player is a pilot.

**Joining.** Join Game, enter the host's address, press Connect. Wait in the lobby for the host to start.

**Joining from a browser or a phone.** A browser cannot host and can only connect over WebSocket; phones usually cannot accept incoming connections either. So browser and phone players join a game hosted on a PC (it listens on UDP 27270 and WebSocket TCP 27271 at once) or, better, a **dedicated server** (see `SERVER.md` in the repository: one command, no player needed on that machine). In the join box:

| You are on | Type | Connects to |
| --- | --- | --- |
| The web game on an `https://` page (for example GitHub Pages) | `wss://tower.example.org` or just `tower.example.org` | the server's TLS proxy on port 443 (browsers on https pages may only use `wss://`) |
| The web game on an `http://` page or `localhost` | `server-host` (port box 27271) or `ws://server-host:27271` | the server's WebSocket port |
| The Android or iPhone/iPad app | the host's address, like on a PC (UDP 27270), or a `ws://` / `wss://` address | ENet, or WebSocket when written as a URL |

A link can do the joining for you: `index.html?join=wss://tower.example.org&name=Ann` opens the web game, fills in your name and connects. The microphone only works on `https://` pages or `localhost`; the browser asks for permission when you enter the lobby. On a touchscreen, hold the big **PTT** button to talk (section 10).

**Microphone.** The lobby shows whether your mic works and a level meter. With no microphone you can listen, and use the text radio for everything you would say (section 3.2).

**Solo practice.** Solo Practice in the main menu opens four offline modes. The AI players speak only on the text radio (they cannot hear voice), so you answer them with the text radio too.

| Mode | You | Who else |
| --- | --- | --- |
| **Fly with an AI tower** | A pilot, starting at an arrival gate. | An AI approach controller ("Approach (AI)") and two AI aircraft. The tower calls you first: radar contact, the ATIS letter and QNH, a heading and a safe altitude. It vectors you round a base leg to a 30° intercept, clears you for the ILS at an altitude that keeps you above the MSA and below the glideslope, and clears you to land at about 7 nm. It repeats instructions you ignore, notices a wrong altimeter setting (you level off a few hundred feet away from your altitude) and warns you below the MSA. |
| **Spot the impostor** | A pilot. | Two AI controllers, **Controller A** and **Controller B**, both "Fallow Approach", and one AI aircraft. One controller is the impostor and it is after you. It starts with plausible vectors, then lies: a wrong QNH, a descent below the MSA, a heading into a hill, a 360 and vectors away to burn your fuel. The real one corrects lies at once ("disregard…") and calls the impostor out; the impostor calls the real one out too. Check every instruction against the ATIS and the plate (section 6). The tower side wins only if both aircraft land. |
| **Be the controller** | The real tower, at the scope. | Four AI aircraft at the arrival gates. They check in, fly exactly what you send them by text, read back WILCO, refuse unsafe instructions with UNABLE and a reason, ask for vectors when you forget them, and declare minimum fuel. |
| **Free flight** | A pilot. | Two AI aircraft and no controller. Learn the cockpit. |

Once your own aircraft has landed and stopped (or crashed), a solo round plays out the rest eight times faster: the clock shows ▶▶.

**Lobby and end screen.** Both are open mic: everyone hears everyone, clean, with no radio effect.

---

## 3. The radio

There is one frequency, **APP 119.850**, shown in the strip across the top of the screen. During a round, it is the only way anyone talks to anyone: by voice (3.1) or by text (3.2). Both share the one frequency.

### 3.1 Voice

| What | How |
| --- | --- |
| Transmit | Hold **Space**, or hold the **PTT** button in the top strip with the mouse. Release to stop. On a touchscreen, hold the big **PTT** button in the bottom-right corner. |
| One person transmitting | Everyone hears them through a radio filter. |
| Two or more transmitting at once | The frequency is **BLOCKED**. Everyone hears a squeal and nobody hears speech. The strip shows BLOCKED in red. |
| Crashed pilot | Cannot transmit. The strip shows RADIO DEAD if you try. |
| Landed pilot | Can still transmit and listen. |
| Lobby, end screen | Open mic. No push-to-talk needed. |

The strip shows IDLE, RX plus who is talking (a pilot's callsign, or a controller's name plus CTL), TX when it is you, and BLOCKED. It also has your role tag, the round clock and the PTT button.

Space does not transmit while you are typing in a text field. In a round that is only the controller scratchpad. Press Enter or click the scope to leave the field.

Wait for the frequency to be clear before you key. If you talk over someone, you block both of you.

### 3.2 The text radio (no microphone needed)

Every standard call can be sent as a text message instead: instructions, readbacks, fuel calls, accusations. You build it from buttons or keys, never free typing, and the game writes it out in standard phraseology, the same for everyone. Every player sees every message, as on a real frequency: pilots in the **DATALINK** panel at the top right of the cockpit view, controllers in the **FREQUENCY** tab of the flight data panel. Messages to your own callsign are marked in amber.

Text obeys the frequency too:

| What | How |
| --- | --- |
| Going out | A message waits until the frequency is clear (nobody holding push-to-talk, no other text going out), then is "on the air" for about as long as it takes to say it, 1.5 to 6 seconds. The strip shows **RX** name **· TEXT**, or **TX TEXT** for your own. Your microphone never opens for text. |
| Blocked | If anyone keys a microphone while a text message is on the air, it is **BLOCKED**: nobody gets it. Its sender sees it in red with a **RESEND** button. |
| Waiting too long | A message that cannot get out within 30 seconds is dropped (**NOT SENT**). You can have at most 3 waiting or going out. |
| Taking turns | When several people have text waiting, whoever spoke least recently goes first. |

**Pilots** (DATALINK panel, keys work while flying):

| Key | Does |
| --- | --- |
| **W** | WILCO (will comply) to the newest instruction for you |
| **U** | UNABLE. **WHY ▾** gives a reason: below the MSA, the QNH is not the ATIS one, terrain, fuel |
| **S** | STANDBY |
| **R** | SAY AGAIN |
| **C** | CALLS: check in, request vectors, established, minimum fuel, mayday fuel (with your real fuel), going around, and **CALL OUT** a controller as the impostor |
| **T** | More or fewer lines |

The reply buttons only show while an instruction for you is waiting for an answer. That instruction stays pinned in the panel until you answer it. Replying does not fly the aircraft: you still set the autopilot yourself. After a crash you can no longer send, but the panel keeps showing the frequency.

**Controllers** (flight data panel, under the flight strip): select a target, then either

- click the **HDG / ALT / SPD / QNH** values (the wheel or − / + changes them, Shift for big steps; a value is included once you touch it, and the turn direction comes from the radar track) and the chips (RADAR CONTACT, EXPECT ILS, CLEARED ILS, CLEARED LAND, GO AROUND, CANCEL APP, 360 LEFT / RIGHT, LOW ALT ALERT, TRAFFIC ALERT, DISREGARD, ROGER), or
- press **Enter** and type shorthand, then Enter again to send (Esc leaves the line):

| Type | Means |
| --- | --- |
| `h270` · `l270` · `r270` | fly heading 270 · turn left · turn right heading 270 |
| `a55` or `a5500` (also `c55`, `d55`) | climb / descend and maintain 5500 (the verb comes from the radar altitude) |
| `s180` | speed 180 knots |
| `q1009` · `q` | QNH 1009 · the ATIS QNH |
| `app` (`ils`) · `land` (`ctl`) · `ga` · `x` | cleared ILS approach · cleared to land · go around · cancel approach clearance |
| `rc` · `exp` | radar contact, information … is current · expect ILS approach |
| `la` · `ta` · `ol` / `or` · `dis` · `rog` | low altitude alert · traffic alert · left / right 360 for spacing · disregard · roger |

The line under it shows exactly what will go out; a QNH that is not the ATIS one shows in amber. Items that cannot go together (a heading with a 360, CLEARED ILS with GO AROUND…) grey out SEND and say why. **SEND** sends it; while three of your messages are still waiting it keeps what you composed and says the frequency is busy. A blocked or unsent message of yours gets **RESEND** in the FREQUENCY tab. Below, **ALL STATIONS**: broadcast the ATIS letter and QNH, or **CALL OUT** the other controller. With `ALT` and `CLEARED ILS` together the message reads "maintain 5500 until established on the localizer, cleared ILS approach".

**Read aloud.** With **Read text-radio messages aloud** on in Settings (on by default where the system has text-to-speech), every message from someone else is spoken by the system's voices, one voice per person, so the two controllers sound different. Your own messages are not read back. These voices do not go through the radio filter. Their loudness follows **Radio / ATC voice** in Settings (with Master).

---

## 4. Pilot guide

### 4.1 What you have

You fly a generic twin jet through its autopilot. You do not steer with a stick. You tell the autopilot what to do: heading, altitude, speed, approach mode, gear, flaps and altimeter setting. Everything else is automatic, including the landing itself.

The top strip shows your callsign and the two controllers' names.

### 4.2 Views and camera

| Input | What it does |
| --- | --- |
| **1** | Panel view (the default). Instruments and the autopilot panel. |
| **2** | Outside view. The windshield. |
| **3** | Pedestal view. Flap lever and landing gear controls. |
| Hold **right mouse button** and move | Look around. Left/right up to 110 degrees, up 35, down 70. Switching view resets it. |
| **Mouse wheel** over empty space | Zoom in (down to about a third of the field of view). Over a knob the wheel turns the knob instead. |

A reminder of the keys appears bottom left at the start and after each view change, then fades.

### 4.3 Keyboard

| Key | Action |
| --- | --- |
| **Space** | Push-to-talk (hold) |
| **Left / Right** | Selected heading -1 / +1 degree (**Shift**: 10) |
| **Up / Down** | Selected altitude +100 / -100 ft (**Shift**: 1000) |
| **Page Up / Page Down** | Selected speed +1 / -1 kt (**Shift**: 10) |
| **[ / ]** | Altimeter setting -1 / +1 hPa (**Shift**: 5) |
| **B** | Altimeter to standard (STD, 1013). Press again to go back to the setting you had. |
| **A** | Arm or disarm approach mode (APPR) |
| **G** | Gear up or down |
| **F** | Flaps down one step |
| **Shift + F** | Flaps up one step |
| **I** | Open or close the ATIS |
| **P** | Open or close the approach plate |
| **1 / 2 / 3** | Panel / outside / pedestal view |
| **W / U / S / R** | Text radio: WILCO / UNABLE / STANDBY / SAY AGAIN to the newest instruction for you (section 3.2) |
| **C** | Text radio: open the CALLS row |
| **T** | Text radio: more or fewer lines |
| **Esc** | Settings menu (this does not close the ATIS or plate) |

Holding a heading, altitude, speed or altimeter key repeats. Gear, flaps, A and B do not repeat.

The ATIS and plate are on a tablet that slides up. Press I or P again, or click its CLOSE button, to put it away. While it is open you cannot click cockpit controls, but the keyboard still works.

Limits: heading 0 to 359, altitude 0 to 20 000 ft in 100 ft steps, speed 140 to 250 kt, altimeter 950 to 1050 hPa, flaps 0 to 3. The speed you select cannot go below the minimum for your flaps (see 4.7).

### 4.4 Mouse

Point at a control. It lights up and a tooltip says what it is and what it is set to.

| Input | What it does |
| --- | --- |
| **Wheel** over a knob | Turn it one step (**Shift**: big step) |
| **Left-drag** a knob | Turn it. Right or up increases. |
| **Click** the baro knob | STD / QNH toggle (same as B) |
| **Click** the APPR button | Arm or disarm the approach (same as A) |
| **Click** the gear lever (or wheel it) | Gear up or down. Wheel down = down. |
| **Click** a flap position on the pedestal | Select that flap setting |
| **Click** the flap lever | One step further. After 3 it goes back to 0. |
| **Wheel** or drag the flap lever | Wheel up = flaps up, wheel down = flaps down |
| **Click** MASTER WARN or MASTER CAUT | Acknowledge the warning light. It stays quiet until a new warning appears. |

Other buttons and knobs on the panel (A/THR, AP1, AP2, V/S, ND mode and range, LS, CSTR, autobrake) are for looks. They do nothing.

### 4.5 The instruments

**Autopilot panel (glareshield)**

| Window | Meaning |
| --- | --- |
| SPD | Selected speed (kt) |
| HDG | Selected heading |
| ALT | Selected altitude (ft, indicated) |
| V/S | Always dashes. Vertical speed is automatic. |
| LOC / APPR | Lit when the approach is armed. LOC also lights when localizer is captured. |
| BARO (left of the panel) | Altimeter setting in hPa. Shows STD when it is 1013. |

The autopilot climbs or descends by itself at about 1800 ft/min (up to 2500 for big descents), turns at 3 degrees per second, and changes speed at about 1.5 kt per second. A window shows what you just commanded straight away. If the server limits it (for example a speed below the flap minimum) it corrects itself after about a second and a half.

**Primary flight display (PFD)**

- Speed tape (left), altitude tape (right) with the selected altitude above it and the baro setting below it (STD or QNH plus the number).
- Attitude indicator with the radio altimeter in the middle once you are within 2500 ft of the ground. Amber when you are at or below the decision altitude.
- Vertical speed scale.
- Heading box and selected heading at the bottom, DME to the field bottom right.
- Mode row on top: speed mode, lateral mode (HDG SEL, then LOC after localizer capture), vertical mode (ends in G/S after glideslope capture), then AP1. While APPR is armed the row also shows CAT 1 and DA 712, with LOC and G/S shown white as armed.
- While on the ILS, "IFTW 109.90" appears bottom left and the localizer (LOC) and glideslope (G/S) needles appear.

**Navigation display (ND)**

- Compass, heading-up. The selected heading bug.
- A pointer to the field with the DME (distance in nm) bottom left: "FTW DME 12.3". This is how you know where the field is.
- The ILS course (270) as a magenta arrow. When you receive the localizer, a deviation bar slides along it (each dot is 1 degree). An amber "LOC" on the display means there is no localizer signal yet.

**Engine and systems display (EICAS)**

- **FUEL: minutes remaining.** Only you can see it. Declare "minimum fuel" by voice when it gets low.
- GEAR (UP / TRANS / DN) and FLAPS (with the minimum speed for the current flaps).
- Warning messages (GPWS TERRAIN, GPWS PULL UP, L/G GEAR NOT DOWN, FUEL LO LEVEL).

**Standby display (ISIS)** shows the altimeter setting in big letters.

### 4.6 The ATIS and the approach plate

**ATIS (press I).** The tablet shows the information letter and these values:

| Item | What it tells you |
| --- | --- |
| **QNH** | The correct altimeter setting. Everything below depends on this. It is between 996 and 1030 and never within 4 hPa of 1013. |
| RWY | Always 27. |
| WIND | Direction and speed. Flavour only. The game has no wind. |
| VIS | Visibility in metres. Fog. |
| CEILING | Overcast cloud base in feet. |

It also shows the full broadcast text, including the transition altitude (6000) and temperature. There is one ATIS for the whole round. Only a player's voice can disagree with it.

**Approach plate (press P).** A real-style chart of ILS RWY 27. Read it before you need it.

| Where | What is there |
| --- | --- |
| Top strip | LOC **IFTW 109.90**. Final approach course **270**. GS at **FALOW 3000'**. ILS DA(H) **712' (200')**. Airport elevation **512'**. |
| MSA box (top right) | Minimum safe altitude by sector within 25 nm of the field. See section 9. |
| Missed approach line | The published missed approach (see 4.9). |
| Alt set line | Altimeter in hPa with the QNH from the ATIS, transition altitude 6000. |
| Plan view | The four hills with their elevations, the fixes, the final approach course, the FAF, the hold at HOLDR, the missed approach track and DME rings. North is up. |
| Profile view | The 3.00 degree glidepath from FALOW, the platform altitude, the DA. |
| Minimums box | S-ILS 27: DA 712'. The localizer-only line is printed too, but the game only lands you on a full ILS. Circling is not authorised. |
| Notes box | The landing requirements, the hold, terrain up to 4900', and that the glideslope captures from below only. |

### 4.7 The altimeter rule

> **Set the ATIS QNH on your altimeter. Then every altitude you read is a true altitude above the sea, and every altitude on the plate and from the tower means what it says.**

The aircraft starts with **1013** set. Fix it first.

The sim works like this:

```
indicated altitude = true altitude + (your setting - real QNH) x 27 ft
```

The autopilot holds **indicated** altitude. So a wrong setting puts the aircraft at the wrong real height:

- If you set a number **higher** than the real QNH, you fly **lower** than the display says: 27 ft per hPa. A QNH that is 10 hPa too high puts you 270 ft closer to the ground.
- If you set a number lower, you fly higher than shown. That is safe but sloppy.

A wrong QNH from a "controller" is one of the cheapest ways to kill a pilot. The terrain does not read your altimeter.

Controllers see your **true** altitude on the scope, not your indicated one.

### 4.8 Flying the ILS 27 step by step

You start 25 to 35 nm out, at 7000 to 10 000 ft, at 250 kt, heading roughly at the field. The approach comes in from the east, flying west on course 270. You must be on the ILS, gear down, flaps 3, 155 kt or less, when you cross the threshold.

| Step | Do this | Check |
| --- | --- | --- |
| 1 | Press **I**. Read the QNH. Set it with **[ ]** (or scroll the baro knob). | The BARO window shows the ATIS QNH. |
| 2 | Listen for the controller. Check each instruction against the ATIS and the plate (section 6). Set the heading and altitude you accept. | HDG and ALT windows show your values. |
| 3 | Slow down early. Speed changes only 1.5 kt per second: 250 to 155 kt takes more than a minute. Put in **flaps** as you slow. | SPD shows your target. The EICAS shows the flap minimum. |
| 4 | Get onto the extended centreline, east of the field, roughly 270. Fly a heading that intercepts it at 30 degrees or less. Arm **A** (APPR). | The APPR light is on. The ND shows the ILS bar. |
| 5 | **Localizer capture** happens by itself: you must be inside the beam (the needle on the scale, 1 dot = 1 degree) within 25 nm, in front of the runway (inside 35 degrees of the extended centreline), intercepting at 90 degrees or less. The autopilot then steers you along the centreline. | LOC mode shows. |
| 6 | Be level at the platform altitude **3000 ft** (selected altitude 3000) before the **FAF, FALOW, 7.7 nm** from the threshold. | PFD altitude 3000, DME above 7.7. |
| 7 | **Glideslope capture** also happens by itself. The glidepath must come up to you **from below**: you intercept it from 3000 ft, level. You cannot capture it from above. The autopilot then flies the 3 degree glidepath (roughly 800 ft/min) and ignores the selected altitude. | G/S mode shows. The VSI shows the descent. |
| 8 | **Gear down** (G) and **flaps 3** (F until it reads 3), **speed 155 kt or less**, well before the threshold. Do it at about 10 nm. (The plate's note 1 lists these requirements.) | EICAS: GEAR DN, FLAPS 3. IAS 155 or less. |
| 9 | Do nothing else. At the threshold the aircraft lands itself, flares and rolls out. | LANDED caption. |
| 10 | Not right? Go around (see 4.9). | |

**Landing requirements** (all four, at the moment you cross the threshold within 0.5 nm of the centreline):

1. Localizer captured **and** glideslope captured.
2. Gear down.
3. Flaps 3.
4. IAS 155 kt or less.

Cross the threshold captured but with something wrong and you crash on the runway (RUNWAY ACCIDENT). Cross it without both captures and you simply do not land: you overfly the runway and are in no position to fly the missed approach. Go around before you get there.

Minimum speeds: flaps 0 is 200 kt, flaps 1 is 180, flaps 2 is 160, **flaps 3 is 135**. The selected speed is held between this minimum and 250 kt. Flaps 3 is the only setting where 155 or less is possible.

The decision altitude is 712 ft. The PFD shows MINIMUMS in amber when you are at it. The game does not force a go-around, but you should not continue if you are not stable.

**If APPR does not capture:** check the baro is not the problem, check you are inside the 35 degree cone east of the field, check the intercept angle, and check the glideslope is coming from below. Disarming (A) and arming again resets it.

### 4.9 Missed approach and the hold

Go around if you are not configured, not on the ILS, or cleared off it.

**Published missed approach:**

> Climb straight ahead to 3000, then climbing right turn heading 060 to 6000 direct HOLDR and hold.

How to fly it in this game (there is no direct-to or hold mode, you use heading):

1. **A**: disarm the approach. This drops the localizer and glideslope. The autopilot returns to heading and altitude hold.
2. Set altitude **3000** and keep heading 270. Gear up (**G**), flaps up (**Shift + F**), speed up.
3. At 3000, set heading **060** and altitude **6000**. Right turn.
4. Head for **HOLDR**: 22 nm from the field on bearing 063 (northeast). The ND pointer shows the field, not HOLDR, so use the plate and your DME.
5. **Hold** at HOLDR: inbound course **240**, **right** turns, minimum altitude **6000**, one-minute legs. Fly inbound 240 to the fix, turn right to 060 (a 180 degree turn takes a minute at standard rate), fly 060 for a minute, turn right to 240, repeat.

Do not carry on west past 5 nm or so. **West Ridge, 4900 ft, is 14 nm west.**

Holding burns fuel. Watch the EICAS.

### 4.10 Warnings

| Warning | Meaning | What to do |
| --- | --- | --- |
| **TERRAIN** (amber) | Your current flight path hits terrain within 30 seconds. | Climb and turn away now. |
| **PULL UP** (red, flashing on the PFD) | The same, within 12 seconds. | Climb immediately. |
| **TOO LOW GEAR** (red) | Below 500 ft over the ground with the gear up. | Gear down, or go around. |
| **LOW FUEL** (amber) | Less than 5 minutes of fuel. | Declare minimum fuel. Land now. |

Warnings show on the PFD, the EICAS and the panel lights, and have a sound. They come late, a few seconds before impact. Do not rely on them.

When you are established on the localizer **and** glideslope, the terrain warning only looks at the hills, not at the ground ahead.

### 4.11 Ways to die

| Outcome | Cause |
| --- | --- |
| **Terrain** | Your true altitude goes below the top of a hill while you are inside its radius. Or below the airfield elevation, 512 ft, anywhere. |
| **Mid-air collision** | Another aircraft is within 0.15 nm **and** 200 ft of you. Both crash. You cannot see other aircraft. |
| **Fuel** | The fuel reaches zero. Fuel runs at one minute per minute. At the start you have enough for a direct approach plus roughly 8 to 14 minutes spare. |
| **Runway accident** | You cross the threshold on the ILS but not stable: wrong flaps, gear up, or faster than 155 kt. |

The four hills are listed in section 9.

When your aircraft crashes, the screen cuts to black and a caption names the cause. You can no longer transmit. After a safe landing the aircraft rolls out and stops, and you can still talk.

---

## 5. Controller guide

### 5.1 What you have

Two displays: the radar **scope** (big, left) and the **flight data** panel (right). A strip across the top has the radio and your role: green **TOWER** if you are real, red **IMPOSTOR** if you are not. You and the other controller see exactly the same scope.

You cannot move aircraft. You can only talk. You also cannot see: fuel, selected altitude, altimeter setting, gear, flaps, or whether an aircraft is captured on the ILS.

The scope updates every **2 seconds**. Targets jump from sweep to sweep. The scope shows **true altitude** in hundreds of feet, rounded.

### 5.2 Scope mouse controls

| Input | What it does |
| --- | --- |
| **Wheel** | Zoom around the cursor |
| **Left-drag** or **middle-drag** | Pan |
| **Double-click** | Reset the view |
| **Click** a target or its data block | Select it. This also silences its sound alert. |
| **Click** empty scope | Deselect |
| **Ctrl + click** a target | Select it and turn its data block by 45 degrees |
| **Right-drag** or **Shift + left-drag** | Measure range and bearing. Starts and ends snap to targets. A click without a drag clears it. |
| **Hold right mouse button** off the scope | Look around the room. It springs back when you let go. |

The measuring line reads like **BRG 270 / 12.3 NM**.

### 5.3 Scope keyboard

| Key | What it does |
| --- | --- |
| **Space** | Push-to-talk (hold) |
| **1-4, 6-9** (top row or keypad) | With a target selected, point its data block: 8 north, 9 northeast, 6 east, 3 southeast, 2 south, 1 southwest, 4 west, 7 northwest |
| **5** | Data block back to automatic placement |
| **F1 to F8** | Map layers: F1 RR, F2 CL, F3 FIX, F4 TERR, F5 MSA, F6 HOLD, F7 PTL, F8 HIST |
| **+** / **-** or **Page Up / Page Down** | Zoom in / out |
| **Home** | Reset the view |
| **Delete** or **Backspace** | Deselect and clear the measuring line |
| **Tab** | Switch between the scope view and the room view |

These keys are ignored while you are typing in the scratchpad.

### 5.4 The menu bar and map layers

Across the top of the scope: click to toggle.

| Button | Layer | Default |
| --- | --- | --- |
| **RR** | Range rings and the compass ticks | on |
| **CL** | Extended runway centreline | on |
| **FIX** | Fixes (waypoints) | on |
| **TERR** | Terrain, with elevations | on |
| **MSA** | MSA sector boundaries and values | on |
| **HOLD** | The hold at HOLDR | on |
| **PTL** | Predicted track: a line showing where each target is in **one minute** | off |
| **HIST** | History dots behind each target | on |
| **RNG-** / **RNG+** | Zoom out / in. The number in between is the current range in nm. | |
| **RST** | Reset the view | |
| **LDR A** | Put all data blocks back to automatic | |

Top right: the field and APP.

### 5.5 Reading a target

```
  SKW412        <- callsign
  030↓ 22       <- altitude in hundreds of ft, trend arrow, ground speed in tens of kt
  ILS27         <- your own scratchpad text, if any
```

- **Altitude** is true altitude in hundreds: 030 means about 3000 ft. The arrow (↑ or ↓) shows a climb or descent of more than 300 ft/min. No arrow means roughly level.
- **Ground speed** is in tens of knots: 22 is 220 kt.
- **History dots** are older positions, a few sweeps apart.
- **A line from the dot** to the data block is the leader.
- A **red X** with CRASH is a crashed aircraft.
- A small square with LND is an aircraft that landed. It disappears after 20 seconds.
- The selected target gets a white outline and a boxed block.

### 5.6 Alerts

Two alerts, both based on true altitude and position:

| Tag | Name | Appears when |
| --- | --- | --- |
| **CA** (red) | Conflict alert | Two flying aircraft are closer than **3 nm and 1000 ft** at the same time. Both are tagged. |
| **LA** (amber) | Low altitude alert (MSAW) | A flying aircraft is below the MSA for its sector and is **not captured on the localizer**. |

The tag flashes over the data block, the callsign shows in the alert list under the status block, and a tone plays (repeating every 15 seconds until you select the target).

Two things worth knowing:

- Separation is **3 nm or 1000 ft**. Either is enough. Both must be violated for CA.
- LA stops as soon as the aircraft captures the localizer. So an LA that clears while the aircraft is on final tells you it has captured. LA uses the sector MSA at any range, even where the readouts show a dash.

### 5.7 The flight data panel

| Section | What it shows |
| --- | --- |
| Header | ATIS letter and QNH. "ON FREQ 119.850 CTL" with the two controller names (you are marked). |
| **Flight strip** | For the selected target: callsign, the pilot's name, the CA / LA / LANDED / CRASHED tag, and **ALT** (feet, with arrow or = for level), **GS** (kt), **TRK** (degrees), **DME** (nm from the threshold), **MSA** (for its sector, within 25 nm). Below it a **scratchpad**. |
| **Datalink clearance** | The text-radio composer for the selected target, and the ALL STATIONS calls (section 3.2). |
| **Traffic** | One line per aircraft: callsign, altitude in hundreds with arrow, ground speed in tens, DME, CA/LA flag. Click a line to select. |
| **Events** | The last 5: landings, crashes, collisions, fuel. |
| Tabs: **FREQUENCY** | The text radio as everyone sees it, newest last (shown first). An UNABLE shows in amber, a blocked or unsent message in red. |
| Tabs: **ATIS** | The ATIS text. |
| Tabs: **ILS RWY 27** | Course 270, platform 3000, FAF FALOW 7.7 nm, glideslope 3.0, DA 712, MSA by sector, the hold, the missed approach. |
| Tabs: **PHRASEOLOGY** | Example calls with the selected callsign and the current QNH and information letter filled in. Click the tab again to close it. |

The scratchpad is **yours only**. Whatever you type (up to 7 letters, capitals) shows as a third line in that target's data block, on your scope only. It is for your notes (for example "HLD", "ILS"). Space is a space while you type. Press Enter to leave the field.

### 5.8 The status block and cursor readout

- Top left of the scope: airport and round clock, ATIS letter and QNH, range and transition altitude, **SEP 3NM/1000FT**, time since the last sweep. If it says NO RADAR DATA or the sweep age is above about 4.5 seconds, the scope is stale.
- Bottom left: with the cursor on the scope, **FTW bearing / range in nm** from the field, and the **MSA** for that point when it is within 25 nm. Use it to read the MSA where you are about to send someone.
- Bottom right: a one-line reminder of the scope controls.

### 5.9 Doing the job

You are the real controller. Your jobs, in order:

1. **Get the ATIS right.** Read the QNH on the flight data panel. Say it on first contact.
2. **Keep everyone at or above the MSA** until they are established on the localizer.
3. **Keep 3 nm or 1000 ft** between aircraft. Aircraft converge onto one final approach course, so sequence them.
4. **Give the approach clearance one aircraft at a time** and only when they can intercept from a sensible angle and altitude (3000 ft platform).
5. **Hold** aircraft at HOLDR at 6000 ft when the approach is busy. Watch the time: pilots have limited fuel and you cannot see it. Ask.
6. **Call out the impostor.** Say clearly on the frequency when the other controller gives a wrong QNH or an unsafe instruction, and tell pilots what to do. The pilots decide whom to obey.

**Phraseology** (from the PHRASEOLOGY tab; callsign SKW412 and QNH 1005 as an example)

| Situation | Say |
| --- | --- |
| First contact | "SKW412, Fallow Approach, radar contact, information Kilo is current, QNH 1005." |
| Descent | "SKW412, descend and maintain 6000, QNH 1005, expect ILS approach runway 27." |
| Vector | "SKW412, turn left heading 180, descend and maintain 4000, QNH 1005." |
| Vector to final | "SKW412, fly heading 300, vectors ILS runway 27." |
| Speed | "SKW412, reduce speed 180 knots." |
| Approach clearance | "SKW412, turn left heading 300, maintain 3000 until established, cleared ILS approach runway 27." |
| Clearance, short | "SKW412, cleared ILS approach runway 27." |
| Landing | "SKW412, runway 27, cleared to land." |
| Hold | "SKW412, hold at HOLDR as published, maintain 6000, expect further clearance in 10 minutes." |
| Go around | "SKW412, go around, climb straight ahead to 3000." |
| Low altitude | "SKW412, low altitude alert, check your altitude immediately, QNH 1005." |
| Traffic | "SKW412, traffic alert, turn right immediately heading 360, climb and maintain 6000." |

Pilots may say "minimum fuel", "MAYDAY MAYDAY MAYDAY, SKW412, fuel, 3 minutes remaining" or "Unable, SKW412, that is below the MSA."

On the text radio the composer builds the same calls (section 3.2). An AI pilot (Be the controller) flies only what you send it in text.

---

## 6. Spotting the impostor (pilots)

You cannot see the other controller's screen. You can only judge what you are told against what you can check. You have the ATIS, the plate and your instruments. Use them.

| Tell | How you check it |
| --- | --- |
| **A QNH that is not the ATIS QNH** | Compare with the ATIS tablet (I). A real tower reads the same number. If you are not sure, set the ATIS one. |
| **A descent below the MSA** before you are established on the localizer | Look at the MSA box on the plate (or section 9). Your sector is the bearing from the field to you, shown on the ND pointer (the reciprocal of the pointer is your bearing from the field). Southwest and northwest are 5900, northeast 5200, southeast 4400. |
| **Vectors toward terrain** | Check the heading against the hills on the plate. If a heading takes you toward Mt Carrow, Saddleback, West Ridge or Tower Hill below the hill's top, say "unable". |
| **Two aircraft cleared for the approach together** | You hear the other callsign. If both are told "cleared ILS" while close, expect a collision. The aircraft ahead should be clear before the next is cleared. |
| **Holding you for a long time** | Watch the fuel on the EICAS. The real tower should ask your fuel. If you are told "hold, expect further clearance" over and over and fuel is falling, declare minimum fuel and ask for the approach. |
| **Descent to 3000 far out** | The platform altitude 3000 is for the final approach inside FALOW (7.7 nm), established on the localizer. Descending that low far out, off the final, is below the MSA. |
| **Wrong runway or wrong airport details** | There is only runway 27. The ILS is 109.90, course 270, DA 712. |
| **Instructions that make no sense physically** | A speed you cannot fly with your flaps, or a heading that turns you away from the approach for no reason. |

Rules of thumb:

- If an instruction **fails a check**, say "unable" and why, on the radio. The real controller can then back you up. On the text radio: **U**, or **WHY ▾** for the reason.
- If you are sure, **CALL OUT** the impostor (text radio CALLS, **C**) so the other pilots hear it.
- The impostor can sound perfect. Do not trust a voice because it is calm.
- The other controller **may also be an honest mistake**. Ask for it to be repeated before you accuse anyone.
- Your safest default is to fly the published procedure yourself: ATIS QNH, stay at or above the MSA, intercept, platform 3000, glideslope. You do not need the controller to land. You do need them to keep you away from other aircraft you cannot see.
- If the two controllers disagree, trust the one whose numbers match the ATIS and the plate.

---

## 7. Playing the impostor

You see the same scope as the real controller. The top strip says IMPOSTOR. You win if **half or fewer** of the aircraft land.

| Pilots | Aircraft that must crash for you to win |
| --- | --- |
| 2 | 1 |
| 3 | 2 |
| 4 | 2 |
| 5 | 3 |
| 6 | 3 |

You have only your voice, or the same text radio as everyone. You cannot touch anyone's aircraft. The pilots fly themselves, and they can check you. Your tools are errors that sound plausible.

What works, and what the sim does about it:

- **A wrong QNH** a few hPa off. Each hPa is 27 ft. Ten hPa too high and a pilot who sets your number flies 270 ft lower than they think. Small errors are hard to spot. Large ones get caught by pilots who read the ATIS.
- **Descents below the MSA** before the aircraft is on the localizer, near the hills. Your scope will show **LA** when you do. The real controller will see it too.
- **Vectors toward the hills.** Mt Carrow (NE), Saddleback (SSE), West Ridge (WSW), Tower Hill (ESE). See section 9.
- **Two aircraft on the approach together.** Clear a second aircraft while the first is still on final, or send two to the same altitude on converging headings. CA will warn the real tower.
- **Holds.** Fuel is the only thing that ends a hold. Pilots see their own fuel and you do not. Holding everyone for a long time takes fuel from them, and you cannot see how much.
- **Sound like the tower.** Use the real phraseology (see 5.9). Flag a pilot's mistakes before they flag yours.
- **Talk over the real controller.** Two people keying blocks the frequency. This also silences you. Use it when a timely warning would hurt you. Holding push-to-talk also blocks a text message on the air, and text waits while you hold it.

Watch the **CA** and **LA** alerts: they mean the real controller is about to speak up.

---

## 8. The end screen

When no aircraft is still flying, the round ends. You see:

- **TOWER WINS** or **IMPOSTOR WINS**, and how many aircraft landed out of how many, and the round time.
- Three cards: **Real tower** (name), **Impostor** (name), and **You**: WON or LOST.
- A table of every aircraft: callsign, pilot, outcome (Landed safely, Flew into terrain, Mid-air collision, Ran out of fuel, Crashed on the runway).
- A timeline of every landing and crash with the round time.

The radio is open mic again. Only the host has the **Back to lobby** button. Everyone else waits for the host to bring them back. Roles are re-dealt on the next Start Round.

---

## 9. Reference: the airport

KFTW, Fallow Ridge Regional. Elevation 512 ft. Runway 27 (heading 270). ILS IFTW 109.90, course 270, glideslope 3.0 degrees, decision altitude 712 ft. DME is from the field. Transition altitude 6000. Radar frequency 119.850.

Positions are given as bearing and distance from the field (the runway 27 threshold), as shown in the scope footer.

**MSA (within 25 nm of the field, by bearing from the field)**

| Bearing from field | MSA |
| --- | --- |
| 000 to 090 | 5200 ft |
| 090 to 180 | 4400 ft |
| 180 to 270 | 5900 ft |
| 270 to 360 | 5900 ft |

The final approach course runs east from the field, right on the boundary between the 5200 and 4400 sectors. Once you are established on the localizer, the MSA alert no longer applies to you.

**Terrain (cylinders: below the top, inside the radius, is a crash)**

| Hill | Where | Radius | Top |
| --- | --- | --- | --- |
| Mt Carrow | bearing 045, 12.7 nm | 3.5 nm | 4200 ft |
| Saddleback | bearing 165, 11.4 nm | 3.0 nm | 3400 ft |
| West Ridge | bearing 258, 14.3 nm | 4.5 nm | 4900 ft |
| Tower Hill | bearing 110, 20.2 nm | 2.0 nm | 2300 ft |

Everywhere else the ground is at 512 ft.

**Fixes**

| Fix | Bearing, distance | Use |
| --- | --- | --- |
| **FALOW** | 090, 7.7 nm | Final approach fix. Glideslope intercept at 3000 ft. |
| RIDGE | 090, 14.0 nm | On the final approach course. |
| **HOLDR** | 063, 22.4 nm | Hold. Missed approach ends here. |
| NORBY | 036, 27.2 nm | Arrival gate |
| EASTO | 086, 30.1 nm | Arrival gate |
| SOLEY | 150, 27.8 nm | Arrival gate |
| WHISK | 312, 26.9 nm | Arrival gate |

**Hold:** HOLDR, inbound course 240, right turns, 6000 ft or above.

**Missed approach:** climb straight ahead to 3000, then climbing right turn heading 060 to 6000 direct HOLDR and hold.

**Numbers that matter**

| What | Value |
| --- | --- |
| Separation | 3 nm or 1000 ft |
| Collision | closer than 0.15 nm and 200 ft |
| Altimeter error | 27 ft per hPa |
| Landing | LOC + G/S captured, gear down, flaps 3, IAS 155 or less |
| Speed range | 140 to 250 kt. Flap minimums: F0 200, F1 180, F2 160, F3 135 |
| Turn rate | 3 degrees per second |
| Climb / descent | about 1800 ft/min, up to 2500 ft/min in a long descent |
| GPWS | TERRAIN within 30 s of impact, PULL UP within 12 s |
| Low fuel | under 5 minutes |
| Radar sweep | every 2 seconds |

---

## 10. Touch controls (phones and tablets)

On a device with a touchscreen (phones and tablets in landscape, touch browsers) the game shows on-screen controls, and everything above can be done without a keyboard. On a Windows, macOS or Linux computer nothing changes, even with a touchscreen; start the game with `--touch` after `--` to force the touch controls on. The buttons are sized for a finger (about 9 mm on a 6-inch phone) and keep clear of notches and rounded corners.

You can use two hands at once: holding **PTT** with one thumb does not stop the other hand from turning knobs, dragging the view or pressing buttons.

**Everywhere**

| Touch | What it does |
| --- | --- |
| Hold **PTT** (bottom right, during a round) | Push-to-talk. Release to stop. It shows TX, RECEIVING, BLOCKED or RADIO DEAD. |
| **MENU** (top right; in the top strip during a round) | Settings: volume (master, ambient noise, radio / ATC voice), fullscreen, reading the text radio aloud, leave game, quit. Same as Esc. |
| Tap a text field | Opens the on-screen keyboard. The screen slides up so the field stays visible. |

**Pilot**

| Touch | What it does |
| --- | --- |
| **PANEL** / **OUTSIDE** / **PEDESTAL** (left column) | The three views (keys 1 / 2 / 3) |
| **ATIS** / **PLATE** (left column) | Open or close that page of the tablet (I / P). Tap again to close. |
| **MASTER WARN** (left column) | Acknowledge the warning light. It is lit while there is a warning. |
| One-finger drag on the view | Look around |
| Pinch | Zoom |
| Double-tap the view | Look straight ahead again, no zoom |
| **HDG** / **ALT** / **SPD** / **BARO** (bottom strip) | Show the selected values. Tap one to choose which one − and + change (it is lit). |
| **−** / **+** | One step down / up. Hold to repeat in big steps (heading 10, altitude 1000, speed 10, altimeter 5). |
| **×10** (×5 for BARO) | While lit, every tap of − / + is a big step |
| **STD** | Altimeter to standard 1013, tap again to go back to your QNH (B) |
| **APPR** | Arm or disarm the approach (A). The small text shows the lateral mode (HDG, LOC, APP). |
| **GEAR** (right column) | Gear up or down (G). Shows UP, TRANS or DOWN. |
| **FLAPS UP** / **FLAPS DN** (right column) | Flaps one step up / down (Shift+F / F). The small text shows the current setting. |
| Tap a cockpit control | Same as a click: APPR button, baro knob (STD), gear lever, flap lever and gates, master warning |
| Drag a cockpit knob | Turns it: right or up increases |

A value shown in amber in the strip has been sent and is waiting for the aircraft to confirm it.

The **DATALINK** panel (top right, between the columns) is the text radio (section 3.2): tap **WILCO**, **UNABLE** (**WHY ▾** for a reason), **STANDBY** or **SAY AGAIN** to answer the instruction marked in amber, **CALLS** for check-in, fuel calls and calling out a controller, **MORE** for more lines.

**Controller**

| Touch | What it does |
| --- | --- |
| One-finger drag on the scope | Pan |
| Pinch | Zoom |
| Tap a target or its data block | Select it (empty scope: deselect). Tap a button in the scope's menu bar to use it. |
| Double-tap | Reset the view |
| **MEASURE** (bottom bar), then drag | Range and bearing line (right-drag on a computer). Tap MEASURE again to pan again. |
| **LAYERS** | Opens the eight map layer buttons (RR, CL, FIX, TERR, MSA, HOLD, PTL, HIST). Lit = on. |
| **ZOOM −** / **ZOOM +** (hold repeats), **RESET** | Range and view |
| **ROOM** | Switch between the scope and the room view (Tab) |
| Drag off the scope | Look around the room. It springs back when you let go. |
| With a target selected: **LDR −45°** / **+45°**, **AUTO** | Turn its data block, or back to automatic |
| **DESEL** | Deselect and clear the measuring line |

The flight data panel (tabs, traffic list, scratchpad, and the text-radio composer: HDG / ALT / SPD / QNH with − / +, the instruction chips, SEND) works with a tap, but only while no other finger is down: let go of PTT first. The scratchpad and the shorthand line open the on-screen keyboard. The same goes for the menus and the tablet's own tab buttons.

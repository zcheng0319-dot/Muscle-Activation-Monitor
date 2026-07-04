# My_EMG M0 validation report

Status: in progress  
Date opened: 2026-07-03  
Scope: hardware and signal-chain validation before M1 implementation

This report records measured or independently reproducible facts only. Empty
tables require physical XIAO ESP32C3 and Cheez.sEMG measurements and must not be
filled from example payloads.

## Protocol notes carried into M0

- The first sample or calibration packet containing `"v": 2` fixes the
  connection as protocol v2 until disconnect. Any first packet without `v`
  is treated as Legacy.
- Retrying an action reuses the same `sessionBaseline`; it does not recalibrate.
- Legacy training history has been retired. Legacy protocol identification is
  retained only to direct users to update the device firmware before Compare.
- `deviceMs` uses `millis()` with uint32 semantics. A backward jump during an
  active comparison aborts that comparison.

## M0-A — CheezsEMG source freeze

| Item | Result |
|---|---|
| Repository | https://github.com/CheezCheez/CheezsEMG |
| Release | `v1.0.2` |
| Annotated tag object | `02350125bd8125cbca10db9300809fd077a30ab9` |
| Peeled source commit | `4df371edf8437f08a686de45ffbd45f5256c8530` |
| Commit date | `2025-12-26T19:49:31+08:00` |
| Library metadata version | `1.0.2` |
| License file | MIT |
| Copied into project firmware directory | No — deferred until M1 approval |

The `v1.0.2` tag is annotated. The reproducible source revision is the peeled
commit, not the tag-object SHA.

Source checksums:

| File | SHA-256 |
|---|---|
| `src/CheezsEMG.cpp` | `D97E902602E677DB10F6F5BEB458D3E3C14FB8B01D07B9F445FE80A63BA8C023` |
| `src/CheezsEMG.h` | `33E39BE9F724971D762A3A3DECD97F854607F2192311B50A6FDFC75D8609D4E9` |
| `LICENSE` | `F1A8E356A7C457096A9D298D7EADA0934C7E4F5C5129BA806182CFD14566F068` |

License review note: the repository declares MIT, but its copyright notice
names “World Famous Electronics LLC” rather than the repository owner. Preserve
the upstream license verbatim when vendoring and review attribution before
distribution.

## M0-B — Filter and envelope audit

Frozen source implements four cascaded second-order sections:

| Section | Numerator `b0,b1,b2` | Denominator `a0,a1,a2` |
|---|---|---|
| 1 | `0.00223489, 0.00446978, 0.00223489` | `1, -0.55195385, 0.60461714` |
| 2 | `1, 2, 1` | `1, -0.86036562, 0.63511954` |
| 3 | `1, -2, 1` | `1, -0.37367240, 0.81248708` |
| 4 | `1, -2, 1` | `1, -1.15601175, 0.84761589` |

Frequency response was evaluated directly from these transfer functions at
`fs = 500 Hz`, normalized to peak gain.

| Measurement | Result |
|---|---:|
| Peak frequency | `87.578 Hz` |
| Peak gain | `0.999999238` |
| -3 dB band | `70.011–109.987 Hz` |
| -6 dB band | `67.581–113.135 Hz` |
| Relative response at 20 Hz | `-73.462 dB` |
| Relative response at 50 Hz | `-31.106 dB` |
| Relative response at 60 Hz | `-17.403 dB` |
| Relative response at 120 Hz | `-13.590 dB` |
| Largest pole magnitude | `0.920661` |

All four sections are stable. `setSampleRate()` changes scheduling only; it does
not recalculate filter coefficients. The audited response therefore applies
only at 500 Hz.

The official envelope is not RMS. It is:

```text
filtered sample
→ absolute value
→ 32-sample moving average using integer storage/arithmetic
→ multiply by 2
```

At 500 Hz, the moving-average window spans 64 ms. MVP terminology must remain
`env` internally and “local EMG activity” in user-facing copy.

## Local toolchain audit

| Item | Result |
|---|---|
| Arduino CLI | `1.4.1` |
| ESP32 Arduino core | `3.3.10` |
| Board FQBN | `esp32:esp32:XIAO_ESP32C3` |
| Installed CheezsEMG library | `1.0.2` |
| Historical pre-M1 firmware compile | Pass |
| Historical pre-M1 firmware flash use | `602381 / 1310720 bytes (45%)` |
| Historical pre-M1 firmware global RAM use | `19192 / 327680 bytes (5%)` |
| Detected serial devices | None |

The compile check validates the local toolchain only. It does not validate ADC,
sampling, BLE timing, or the new firmware design.

## M0-C — ADC range and clipping

Status: blocked until the physical XIAO ESP32C3 is connected.

Record the exact board/core configuration and do not infer values from example
JSON.

| Scenario | Raw min | Raw max | Samples at/near 0 | Samples at/near 4095 | Clip ratio |
|---|---:|---:|---:|---:|---:|
| Sensor powered, not attached | `2189` | `2248` | `0 / 5004` | `0 / 5004` | `0.000%` |
| Sensor powered, not attached — repeat | `2188` | `2249` | `0 / 5006` | `0 / 5006` | `0.000%` |
| Attached and relaxed — 30 s | `1402` | `3178` | `0 / 15003` | `0 / 15003` | `0.000%` |
| Light sustained contraction — 15 s | `1354` | `3179` | `0 / 7505` | `0 / 7505` | `0.000%` |
| Strong sustained contraction — 10 s | `718` | `3512` | `0 / 5004` | `0 / 5004` | `0.000%` |
| Strongest safe isometric contraction — 5 s | `0` | `4095` | `13 / 2503` | `70 / 2503` | `3.316%` near either rail |
| Strongest safe isometric — repeat, 5 s | `0` | `4095` | `2 / 2499` | `15 / 2499` | `0.680%` near either rail |

Configuration to record:

| Item | Result |
|---|---|
| Explicit attenuation setting |  |
| ADC resolution |  |
| Sensor supply voltage |  |
| D0 voltage measured at rest |  |
| D0 maximum measured voltage |  |

## M0-D — 500 Hz sampling stability

Status: complete for aggregate scheduler stability, both without and with an
active BLE subscriber.

| Item | Result |
|---|---:|
| Test duration | `60 s` |
| Expected samples | `30000` |
| Measured elapsed time | `60006 ms` |
| Expected samples over measured elapsed time | `30003.0` |
| Actual samples | `30003` |
| Net missing samples | `0` |
| Mean interval | `2000.000 us` |
| Interval standard deviation | `138.719 us` |
| Maximum interval | `6092 us` |
| BLE connected during this run | No |
| Sampling loss while BLE notifying | `0` net samples over 60.011 s |

Interpretation: the scheduler preserved the expected aggregate sample count
over 60 seconds without a BLE client. Individual intervals were not perfectly
uniform; the observed 6.092 ms maximum indicates late samples followed by
catch-up behavior. The BLE-connected run must determine whether notification
work materially worsens this tail.

BLE-connected run: 60.011 s, expected `30005.5` samples, actual `30006`, mean
interval `1999.998 us`, interval SD `138.283 us`, maximum interval `6092 us`,
and `bleConnected=1`. Relative to the disconnected run, 50 Hz notifications did
not cause aggregate sampling loss or worsen the observed maximum interval.

## M0-E — BLE 50 Hz delivery

Status: deferred by product decision. Firmware-side operation with an active
subscriber has been verified, but client-side `seq` receipt has not been
measured. This item is conditionally accepted for M1 only if the App implements
runtime gap monitoring and the result is not represented as a passed delivery
test.

| Item | Result |
|---|---|
| Phone model | `Samsung Galaxy S25 Ultra` |
| Android version |  |
| Negotiated MTU |  |
| Test duration | `60 s` |
| Expected notifications | `3000` |
| Received notifications |  |
| Missing `seq` count |  |
| Missing ratio |  |
| Backward `deviceMs` events |  |
| Largest forward time gap |  |

Observed facts:

- The Samsung Galaxy S25 Ultra connected and subscribed successfully
  (`bleConnected=1`).
- During an active 50 Hz subscription, the firmware produced 30006 of 30005.5
  expected 500 Hz samples over 60.011 seconds, with no aggregate sampling loss.
- The M0 client path did not consume v2 `seq`, so actual phone-side notification
  loss remained unmeasured at this milestone.

Risk acceptance: proceed without a dedicated M0 client collector; require M1
App telemetry to count `seq` gaps and reject/flag incomplete action windows.

## M0-F — Baseline and noise candidates

Status: partially complete and accepted with a documented limitation.

The first pass may record mean and standard deviation for comparison with the
proposed report template. Robust alternatives such as median, MAD, windowed
drift, and clipping ratio must also be retained for threshold evaluation.

| Scenario | Mean env | SD env | Median env | MAD env | Drift | Candidate quality |
|---|---:|---:|---:|---:|---:|---|
| Good attachment, relaxed — 30 s | `87.0610` | `13.1344` | Pending | Pending | Pending | Do not classify yet |
| Light sustained contraction — 15 s | `92.0477` | `14.6404` | Pending | Pending | Pending | Do not classify yet |
| Strong sustained contraction — 10 s | `99.3709` | `26.0558` | Pending | Pending | Pending | Do not classify yet |
| Strongest safe contraction — 5 s | `383.7587` | `159.7203` | Pending | Pending | Pending | Clipping detected |
| Strongest safe contraction — repeat, 5 s | `255.6815` | `99.1720` | Pending | Pending | Pending | Clipping detected |
| Electrode slightly loose — 15 s | `953.8505` | `260.8143` | Pending | Pending | Pending | Bad candidate |
| Electrode detached | `2.5040` | `1.2906` | Pending | Pending | Pending | Do not classify yet |
| Cable movement after reattachment — 15 s | `13.8220` | `4.6645` | Pending | Pending | Pending | Inconclusive |
| Same reattachment, stationary control — 15 s | `22.7551` | `7.2435` | Pending | Pending | Pending | New placement scale |
| Reattached relaxed robust run 1 — 30 s | `193.9135` | `14.3127` | `192` | `10` | `22.7720` | Unstable across runs |
| Reattached relaxed robust run 2 — known movement, 30 s | `239.8310` | `114.3469` | `212` | `14` | `425.0840` | Invalid: user moved |
| Reattached relaxed robust run 3 — 30 s | `129.6616` | `11.2218` | `128` | `6` | `18.1640` | Stable within run |

Detached capture details: 10.007 s, 5004 samples, env range `0–8`, no
near-rail or exact-rail ADC samples. This detached state does not produce an
obvious zero or rail signature, so `no_signal`/attachment inference cannot be
based on raw rails alone.

Detached repeat: 10.011 s, 5006 samples, raw `2188–2249`, env `0–6`,
env mean `2.5745`, env SD `1.3026`, and zero clipped samples. Mean env differed
from the first run by `0.0705` (`2.82%` relative to the first mean); the two
stationary detached runs are closely repeatable.

Attached relaxed capture: 30.007 s, 15003 samples, raw `1402–3178`, env
`54–208`, env mean `87.0610`, env SD `13.1344`, and zero clipped samples.
The attached relaxed envelope is clearly separated from both detached runs on
this placement, but this single observation is not sufficient to define a
general wear-detection or quality threshold. Windowed drift, median, and MAD
remain pending.

Light sustained contraction capture: 15.010 s, 7505 samples, raw `1354–3179`,
env `56–190`, env mean `92.0477`, env SD `14.6404`, and zero clipped samples.
The mean was only `5.73%` above the preceding relaxed run. This qualitative
“light” effort is not cleanly separated from the relaxed distribution and must
not be used to set an activation or quality threshold.

Strong sustained contraction capture: 10.008 s, 5004 samples, raw `718–3512`,
env `34–250`, env mean `99.3709`, env SD `26.0558`, and zero clipped samples.
The mean was `14.14%` above the relaxed run, with substantially greater
variance. The distributions still overlap; a single whole-window mean does not
cleanly encode the stated effort level.

Strongest safe isometric capture: 5.006 s, 2503 samples, raw `0–4095`, env
`110–976`, env mean `383.7587`, and env SD `159.7203`. Near-low samples:
`13` (`0.519%`); near-high samples: `70` (`2.797%`); exact zero samples:
`9` (`0.360%`); exact 4095 samples: `69` (`2.757%`). Combined near-rail ratio:
`3.316%`; combined exact-rail ratio: `3.116%`.

This run proves that the current XIAO ESP32C3 ADC configuration can clip both
ends during the strongest tested contraction, predominantly at the upper rail.
The resulting envelope may be biased and the M1 signal path must not assume the
full Cheez output swing is captured linearly. M0 must determine whether the
clipping originates from the sensor output itself or the ESP32-C3 ADC input
range before freezing ADC configuration and quality thresholds.

Strongest-safe repeat: 4.999 s, 2499 samples, raw `0–4095`, env `80–654`,
env mean `255.6815`, and env SD `99.1720`. Near-low samples: `2` (`0.080%`);
near-high samples: `15` (`0.600%`); exact zero: `1` (`0.040%`); exact 4095:
`15` (`0.600%`). Combined near-rail ratio: `0.680%`; combined exact-rail
ratio: `0.640%`.

The repeat had materially lower envelope magnitude and clipping prevalence than
the first maximum attempt, but it again reached both exact ADC rails. Clipping
is therefore reproducible under maximum safe effort, while its severity varies
substantially between attempts.

Slightly loose electrode capture: 15.009 s, 7505 samples, raw `0–4095`, env
`0–1702`, env mean `953.8505`, and env SD `260.8143`. Near-low samples:
`984` (`13.111%`); near-high samples: `727` (`9.687%`); exact zero samples:
`620` (`8.261%`); exact 4095 samples: `727` (`9.687%`). Combined near-rail
ratio: `22.798%`; combined exact-rail ratio: `17.948%`.

This deliberately loose placement produced a clear bad-signal signature:
extreme envelope inflation, high variability, and heavy clipping at both ADC
rails. A clipping-ratio quality rule is therefore strongly supported for
detecting this failure mode, without labeling it specifically as “not worn.”

Cable-movement capture after fully reattaching the electrodes: 15.011 s, 7505
samples, raw `2045–2380`, env `2–28`, env mean `13.8220`, env SD `4.6645`, and
zero clipping. The immediately following stationary control at the same
reattachment was 15.002 s, 7501 samples, raw `1758–2632`, env `6–62`, env mean
`22.7551`, env SD `7.2435`, and zero clipping.

The cable movement did not inflate the envelope in this trial; its mean was
lower than the paired stationary control. This test therefore does not support
classifying gentle cable movement as a high-noise failure. More importantly,
the stationary mean after reattachment (`22.7551`) was `73.86%` below the
original attached-relaxed mean (`87.0610`). Reattachment materially changed the
signal scale, strongly supporting the product restriction that comparisons are
valid only within one uninterrupted placement/calibration session.

After flashing the enhanced statistics diagnostic, two consecutive 30-second
captures were requested without changing the reattached placement:

- Run 1: raw `1040–3373`, env `148–316`, mean `193.9135`, SD `14.3127`,
  median `192`, MAD `10`, 30 one-second window means spanning
  `184.6160–207.3880` (range `22.7720`), zero clipping.
- Run 2: raw `0–4095`, env `148–876`, mean `239.8310`, SD `114.3469`,
  median `212`, MAD `14`, one-second window means spanning
  `192.7080–617.7920` (range `425.0840`), near-low `5`, near-high `145`,
  exact zero `4`, and exact 4095 `144`.

The user confirmed movement during run 2; it is intentionally retained as a
known contaminated example and excluded from normal-baseline assessment.

Run 3, repeated without intentional movement: raw `1455–2973`, env `98–238`,
mean `129.6616`, SD `11.2218`, median `128`, MAD `6`, 30 one-second means
spanning `120.3320–138.4960` (range `18.1640`), and zero clipping. It was stable
within the 30-second window, but its median was `33.33%` lower than run 1
despite no reported reattachment between those runs.

Quality gating must therefore evaluate within-calibration drift and clipping,
and the session baseline must remain local to the accepted calibration. A
single global baseline/noise threshold cannot be frozen from the current data.

## Calibration failure-reason framework

Names are provisionally frozen; numeric thresholds are not.

| Reason | Meaning | M0 threshold |
|---|---|---|
| `insufficient_samples` | Too few usable calibration samples | TBD |
| `unstable_baseline` | Baseline variation or drift is too high | TBD |
| `clipping_detected` | Excessive ADC rail clipping | TBD |
| `no_signal` | Envelope is flat or effectively absent | TBD |
| `internal_error` | Firmware sampling or processing failure | Non-numeric |

`not_worn` is intentionally excluded because this hardware connection has no
wear-detection line.

## Provisional calibration gates derived from M0

These are engineering starting points for M1, not validated physiological
thresholds. They must remain named constants and be revisited in M5.

| Gate | Provisional M1 rule | Evidence/limitation |
|---|---|---|
| `insufficient_samples` | Fewer than `1400` samples in a 3 s / 500 Hz rest capture | Allows up to 6.7% loss; client BLE loss is separate |
| `clipping_detected` | More than `0.1%` raw samples at/near either ADC rail during rest calibration | Stable rest runs had zero; known movement and loose contact clipped |
| `unstable_baseline` | One-second mean range divided by median env exceeds `25%` | Stable runs were about 11.9% and 14.2%; known movement exceeded 200% |
| `no_signal` | Not frozen | Robust detached median/MAD capture was not completed; do not infer `not_worn` |
| `internal_error` | Sampling/processing state invalid or non-finite | Structural failure, no numeric threshold |

The earlier two detached captures were closely repeatable (means `2.5040` and
`2.5745`) but did not include median/MAD. A later robust detached capture was
attempted but the Windows `usbser` interface entered a semaphore/write-timeout
state. The missing robust detached result prevents freezing a defensible
`no_signal` threshold. M1 should initially omit this automatic failure reason
or report it only as diagnostic information.

## M0-discovered protocol requirement

Maximum safe contractions repeatedly reached exact ADC rails, and a loose
electrode produced a 22.798% near-rail ratio. The App cannot assess this from
`env` alone because clipping has already distorted the official filter input.

Keep the normal 50 Hz sample packet unchanged:

```json
{"v":2,"type":"sample","env":36.8,"deviceMs":36460,"seq":1823}
```

Add a separate low-rate quality packet, recommended once per second:

```json
{
  "v":2,
  "type":"quality",
  "deviceMs":36460,
  "rawSamples":500,
  "nearRailSamples":0,
  "clipRatio":0.0
}
```

This preserves the frozen lightweight sample schema while allowing the App to
invalidate clipped action windows. Exact quality-packet fields require approval
before M1.

## USB recovery note

After the final BLE/USB test sequence, Windows continued to enumerate the XIAO
as `USB\VID_303A&PID_1001` on COM4, but serial writes and esptool USB reset
failed with semaphore/write timeouts. Closing Arduino IDE, disconnecting the
phone, replugging XIAO, and esptool `--before usb-reset` did not recover it.
Physical BOOT access was unavailable.

The board is not proven damaged; this is consistent with a stuck Windows USB
serial state. Restart Windows or disable/re-enable the COM4 USB device before
the next upload. M1 validation cannot begin until upload access is restored.

## M1 entry decision

Current status: **conditionally ready for implementation planning, not ready
for board validation**.

Completed:

- M0-A source freeze and license audit.
- M0-B reproducible filter/envelope audit.
- M0-C ADC range and clipping scenarios.
- M0-D 500 Hz stability with and without a BLE subscriber.
- M0-F representative normal, movement-contaminated, loose, detached, and
  contraction scenarios, with the robust-detached limitation above.

Conditionally deferred:

- M0-E phone-side notification loss. M1 must count `seq` gaps at runtime.

Before M1 code is finalized:

1. Approve or reject the separate once-per-second quality packet.
2. Recover XIAO upload access for later M1 validation.
3. Treat the calibration thresholds above as provisional M1 constants, with
   mandatory M5 retuning.

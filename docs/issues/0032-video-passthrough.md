# 0032: Video passthrough: HDMI OUT shows the selected DUT's video

Status: Open
Opened: 2026-11-25 (lead, agreed direction with owner: the KVM's monitor path)

Today HDMI OUT always shows the FPGA console. Design brief US-04/US-11: the
monitor shows the selected target's video where available, else a clear
status screen. With no frame buffer (no DDR), pass the HDMI IN pixel stream
straight to HDMI OUT in the recovered pixel clock domain when the video
target is this board's capture-capable DUT and video is locked; fall back
to the console (local 27 MHz timing) otherwise. Glitch-free clock switch
(BUFGCTRL/BUFGMUX) between the console pixel clock (and its 5x serial
clock) and the dvi2rgb recovered clocks; the DVI transmitter must re-lock /
be reset cleanly on a switch. Console auto screen choice (0029) then means:
video present -> passthrough; no video -> no-video screen; selecting ->
select screen (later: optionally overlaid on the live video).

## 2026-11-25 progress (sub-agent, branch feature/video-passthrough)

Design:

* **When**: `supervisor_core` raises `pt_request` (registered) when the
  console screen is on auto (key 0x0035 not 1..3), the hotkey is not
  selecting, text is not forced (control byte b0), the video target is one
  of this board's DUTs (`sel_vid < 2`; phase 1: both share the one HDMI IN)
  and its video is present (`vid_b1`: dvi2rgb locked + active video
  measured). Heartbeat byte 109 reads 3 = passthrough while the switch
  sequencer reports it active (ADR 0005, proto_pkg, dutproto.h,
  netproto.py; `dutctl listen` prints `screen passthrough`). The console
  screen logic is otherwise unchanged and is what shows on fallback.
* **Clocks**: dvi2rgb's SerialClk is a BUFIO (I/O clocks of the HDMI IN
  bank only); our TX serialises in fabric at 5x, so it cannot use it. A
  PLLE2 on the recovered PixelClk (already on a BUFG) makes a phase-aligned
  1x/5x pair: VCO = 35 x f (945 MHz at 27 MHz; lock range ~22.9..45.7 MHz,
  covering dvi2rgb's kClkRange 5 band). Two BUFGCTRLs select console (I0,
  the unbuffered vclk MMCM outputs) or passthrough (I1) on the S pins
  (asynchronous-safe), CE high; IGNORE1 = 1 so switching back never waits
  for an edge of a recovered clock that may have stopped (no hang),
  IGNORE0 = 0 (the console clock never stops). PLL reset = RX unlocked or
  the sequencer's watchdog (RX locked, PLL not, 10 ms).
* **Sequencing** (`video_pt_ctrl`, vendor neutral, clk_sys): request + RX
  + PLL locked for 100 ms -> TX reset, select passthrough after 16 cycles,
  release after 16 ms -> active. Request dropped or source lost -> select
  console at once, TX reset 16 ms. The data mux (decoded stream registered
  once in the vin_pclk domain vs the text renderer) uses the same select,
  which only changes while the TX is in reset; the TX reset is synchronised
  in the (muxed) serial clock domain and dvi_tx re-aligns its symbol load
  after it. A source lost during entry or within 2 s of passthrough is a
  failed attempt: re-entry waits 1, 2, 4, 8 s (resets after 2 s of stable
  passthrough). A user-dropped request has no holdoff.
* **Timing**: the PLL clocks are auto-derived from `hdmi_rx_clk`, so the
  existing async clock groups already separate them from the console pair;
  inside each group the paths into the TX are timed.

Self-loop (HDMI OUT cabled to HDMI IN, as on the bring-up board): the
console output locks the RX, so passthrough is requested; entering it holds
the TX in reset (TMDS clock lane static), the RX unlocks within
microseconds, the sequencer falls back to the console and backs off. It
cannot latch: the loop never gets past the reset window. Expect the monitor
to see one short dropout per attempt, at 1, 2, 4, 8, 8, ... s intervals
(plus ~1-2 s for video_meas to report video present again). Forcing a
console screen (`dutctl set console-screen 1`) or selecting another board's
target stops the attempts.

Tests: `tb_video_pt_ctrl` (debounce, select only changes in TX reset,
immediate fallback, no holdoff after a user drop, self-loop model: attempt
spacing doubles and never latches, recovery, PLL watchdog);
`tb_supervisor_core` (request on auto with video present; heartbeat 109 = 3
then 0 after key 0x0035 = 1). `make test` exit 0.

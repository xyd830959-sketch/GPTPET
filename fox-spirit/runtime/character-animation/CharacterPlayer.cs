using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace GptPet.Animation {
    public sealed class CharacterSoundCue : EventArgs {
        public string Action { get; private set; }
        public long Serial { get; private set; }
        public long Frame { get; private set; }
        public CharacterSoundCue(string action, long serial, long frame) { Action=action; Serial=serial; Frame=frame; }
    }
    public sealed class Clip {
        public string Path;
        public bool Prepared;
        public bool Loop;
    }

    // This object has no WPF dependencies. Only the owning UI thread consumes frames.
    public sealed class VideoSession : IDisposable {
        readonly object gate = new object();
        readonly Queue<byte[]> frames = new Queue<byte[]>();
        readonly Queue<byte[]> recycled = new Queue<byte[]>();
        readonly Thread worker;
        readonly string executable, input;
        readonly int width, height, fps;
        readonly bool loop;
        Process process;
        bool stopping, complete;
        string error = "", stderr = "";
        long lastFrameTicks;
        int frameCount;
        readonly Stopwatch playbackClock = new Stopwatch();
        long nextFrameNumber;
        public const int BufferLimit = 6;

        public VideoSession(string executable, string input, int width, int height, int fps, bool loop) {
            if (width < 1 || width > 1024 || height < 1 || height > 1024 || fps < 1 || fps > 60)
                throw new ArgumentOutOfRangeException("Frame dimensions or rate");
            this.executable = executable; this.input = input;
            this.width = width; this.height = height; this.fps = fps; this.loop = loop;
            lastFrameTicks = Stopwatch.GetTimestamp();
            worker = new Thread(ReadVideo); worker.IsBackground = true; worker.Name = "GPTPET video decoder";
            worker.Start();
        }
        public bool Complete { get { lock (gate) return complete; } }
        public string Error { get { lock (gate) return error; } }
        public int PendingFrames { get { lock (gate) return frames.Count; } }
        public int FrameCount { get { lock (gate) return frameCount; } }
        public long PresentedIndex { get { lock (gate) return nextFrameNumber-1; } }
        public int ProcessId { get { lock (gate) { try { return process == null ? 0 : process.Id; } catch { return 0; } } } }
        public double SecondsSinceFrame {
            get { return (Stopwatch.GetTimestamp() - Interlocked.Read(ref lastFrameTicks)) / (double)Stopwatch.Frequency; }
        }
        static string Quote(string value) {
            if (value.IndexOfAny(new char[] { '"', '\r', '\n', '\0' }) >= 0)
                throw new ArgumentException("Invalid decoder argument");
            return "\"" + value + "\"";
        }
        void ReadVideo() {
            Process owned = null;
            try {
                string filter = "format=rgba,scale=" + width + ":" + height +
                    ":force_original_aspect_ratio=decrease,pad=" + width + ":" + height +
                    ":(ow-iw)/2:oh-ih:color=black@0,format=bgra";
                var info = new ProcessStartInfo(executable);
                info.UseShellExecute = false; info.CreateNoWindow = true;
                info.RedirectStandardInput = true; info.RedirectStandardOutput = true; info.RedirectStandardError = true;
                // libvpx-vp9 is selected explicitly: the default VP9 decoder can lose WebM alpha.
                info.Arguments = "-hide_banner -loglevel error -nostdin " +
                    (loop ? "-stream_loop -1 " : "") + "-c:v libvpx-vp9 -i " + Quote(input) +
                    " -an -sn -dn -vf " + Quote(filter) + " -r " + fps +
                    " -threads 1 -f rawvideo -pix_fmt bgra pipe:1";
                owned = new Process(); owned.StartInfo = info;
                owned.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) {
                    if (e.Data == null) return;
                    lock (gate) {
                        stderr = stderr + e.Data + "\n";
                        if (stderr.Length > 4096) stderr = stderr.Substring(stderr.Length - 4096);
                    }
                };
                lock (gate) {
                    if (stopping) return;
                    process = owned;
                    if (!owned.Start()) throw new IOException("Decoder did not start");
                    owned.StandardInput.Close();
                    owned.BeginErrorReadLine();
                }
                Stream stream = owned.StandardOutput.BaseStream;
                int frameSize = checked(width * height * 4);
                while (true) {
                    lock (gate) { if (stopping) break; }
                    byte[] pixels;
                    lock (gate) pixels = recycled.Count > 0 ? recycled.Dequeue() : null;
                    if (pixels == null) pixels = new byte[frameSize];
                    int offset = 0;
                    while (offset < frameSize) {
                        int count = stream.Read(pixels, offset, frameSize - offset);
                        if (count == 0) break;
                        offset += count;
                    }
                    if (offset == 0) break;
                    if (offset != frameSize) throw new InvalidDataException("Incomplete BGRA frame");
                    lock (gate) {
                        if (stopping) break;
                        // Backpressure: do not discard animation frames while the UI waits.
                        while (frames.Count >= BufferLimit && !stopping) Monitor.Wait(gate, 100);
                        if (stopping) break;
                        frames.Enqueue(pixels); frameCount++;
                    }
                    Interlocked.Exchange(ref lastFrameTicks, Stopwatch.GetTimestamp());
                }
                // Wait only on the background reader; never block the WPF thread.
                owned.WaitForExit();
                lock (gate) {
                    if (!stopping && owned.ExitCode != 0)
                        error = "Decoder exit " + owned.ExitCode + ": " + stderr.Trim();
                    else if (!stopping && frameCount == 0)
                        error = "Decoder produced no frames";
                }
            } catch (Exception e) {
                lock (gate) { if (!stopping) error = e.GetType().Name + ": " + e.Message; }
            } finally {
                lock (gate) { process = null; complete = true; }
                if (owned != null) {
                    try { if (!owned.HasExited) owned.Kill(); } catch { }
                    try { owned.Dispose(); } catch { }
                }
            }
        }
        public void Recycle(byte[] pixels) {
            if (pixels == null) return;
            lock (gate) {
                if (!stopping && recycled.Count < BufferLimit+2) recycled.Enqueue(pixels);
            }
        }
        public bool TryTakeDue(out byte[] pixels) {
            lock (gate) {
                pixels = null;
                if (frames.Count == 0) return false;
                if (!playbackClock.IsRunning) playbackClock.Start();
                long due = (long)(playbackClock.Elapsed.TotalSeconds * fps);
                if (frames.Count > 0 && nextFrameNumber <= due) {
                    pixels = frames.Dequeue(); nextFrameNumber++;
                }
                Monitor.PulseAll(gate);
                return pixels != null;
            }
        }
        public void Pause() { lock (gate) playbackClock.Stop(); }
        public void Resume() {
            lock (gate) {
                if (nextFrameNumber > 0) playbackClock.Start();
                Interlocked.Exchange(ref lastFrameTicks, Stopwatch.GetTimestamp());
            }
        }
        public void Dispose() {
            lock (gate) {
                if (stopping) return;
                stopping = true; frames.Clear(); recycled.Clear();
                Monitor.PulseAll(gate);
                if (process != null) {
                    try { if (!process.HasExited) process.Kill(); } catch { }
                }
            }
        }
    }

    public sealed class CharacterPlayer : IDisposable {
        sealed class Still {
            public BitmapSource Source;
            public byte[] Pixels;
            public int Width, Height;
            public Still(string path, int outputWidth, int outputHeight, int footY, int targetFootY) {
                var bitmap = new BitmapImage();
                bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.UriSource = new Uri(System.IO.Path.GetFullPath(path)); bitmap.EndInit(); bitmap.Freeze();
                var converted = new FormatConvertedBitmap(bitmap, PixelFormats.Bgra32, null, 0);
                converted.Freeze();
                BitmapSource display = converted;
                if (footY > 0) {
                    if (footY >= bitmap.PixelHeight || targetFootY < 1 || targetFootY >= outputHeight)
                        throw new ArgumentOutOfRangeException("Foot anchor");
                    double fit = Math.Min(outputWidth / (double)bitmap.PixelWidth, outputHeight / (double)bitmap.PixelHeight);
                    double left = (outputWidth - bitmap.PixelWidth * fit) / 2;
                    double top = targetFootY - footY * fit;
                    var visual = new DrawingVisual();
                    using (DrawingContext drawing = visual.RenderOpen())
                        drawing.DrawImage(converted, new Rect(left, top, bitmap.PixelWidth * fit, bitmap.PixelHeight * fit));
                    var rendered = new RenderTargetBitmap(outputWidth, outputHeight, 96, 96, PixelFormats.Pbgra32);
                    rendered.Render(visual); rendered.Freeze();
                    var normalized = new FormatConvertedBitmap(rendered, PixelFormats.Bgra32, null, 0);
                    normalized.Freeze(); display = normalized;
                }
                Source = display; Width = display.PixelWidth; Height = display.PixelHeight;
                Pixels = new byte[checked(Width * Height * 4)]; display.CopyPixels(Pixels, Width * 4, 0);
            }
        }
        readonly Image image;
        readonly Still idleStill, clickStill, dragStill;
        readonly Clip idle, click, dragEnter, dragLoop;
        public Clip DragReturn { get; set; }
        readonly Dictionary<string,Clip> extraClips = new Dictionary<string,Clip>();
        readonly Dictionary<string,int> extraCueFrames = new Dictionary<string,int>();
        bool extraCueIssued;
        public string[] RegisteredActions { get { return new List<string>(extraClips.Keys).ToArray(); } }
        public bool HasAction(string name) { Verify(); return name != null && extraClips.ContainsKey(name); }
        public void RegisterAction(string name, Clip clip, int cueFrame) {
            Verify();
            if (name != "wave" && name != "laugh" && name != "yawn") throw new ArgumentException("Unknown gesture");
            if (clip == null || !clip.Prepared || clip.Loop || !File.Exists(clip.Path) || cueFrame < 0 || cueFrame > fps*5)
                throw new ArgumentException("Invalid gesture clip");
            extraClips[name] = clip; extraCueFrames[name] = cueFrame;
        }
        public bool PlayAction(string name) {
            Verify();
            if (!enabled || !visible || State == "drag" || !HasAction(name) || State == name) return false;
            EnterState(name); return true;
        }
        readonly string decoderPath;
        readonly int width, height, fps, staticClickMs;
        readonly DispatcherTimer timer;
        readonly Stopwatch clock = Stopwatch.StartNew();
        VideoSession session;
        VideoSession warmIdle;
        VideoSession readyDragLoop;
        BitmapSource warmIdleBitmap;
        byte[] warmIdlePixels;
        WriteableBitmap videoBitmap;
        byte[] heldVideoPixels;
        byte[] shownPixels;
        int shownWidth, shownHeight;
        byte[] transitionFrom, transitionBuffer;
        long transitionStarted;
        int transitionMs;
        long clickDeadline;
        long lastPresentedTicks;
        readonly EventHandler renderingHandler;
        bool visible = true, enabled = true, disposed;
        string phase = "idle";
        long actionSerial;
        bool clickCueIssued, dragCueIssued;
        public event EventHandler<CharacterSoundCue> SoundCue;
        public event EventHandler AudioStopRequested;
        public string LastAudioCallbackError { get; private set; }
        public string State { get; private set; }
        public string Status { get; private set; }
        public string LastError { get; private set; }
        public int FailureCount { get; private set; }
        public bool DecoderActive { get { return session != null; } }
        public bool TimerRunning { get { return timer.IsEnabled; } }
        public int BufferedFrames { get { return session == null ? 0 : session.PendingFrames; } }
        public int DecoderProcessId { get { return session == null ? 0 : session.ProcessId; } }
        public long RenderedFrameCount { get; private set; }
        public double MaxFrameGapMs { get; private set; }
        public int WarmIdleProcessId { get { return warmIdle == null ? 0 : warmIdle.ProcessId; } }
        public int PreloadedDragProcessId { get { return readyDragLoop == null ? 0 : readyDragLoop.ProcessId; } }
        public int TransitionMs {
            get { return transitionMs; }
            set { Verify(); if (value < 0 || value > 200) throw new ArgumentOutOfRangeException("TransitionMs"); transitionMs = value; }
        }
        public bool IsTransitioning { get { return transitionFrom != null; } }
        public long BlendedFrameCount { get; private set; }

        public CharacterPlayer(Image image, string idleImage, string clickImage, string dragImage,
            Clip idle, Clip click, Clip dragEnter, Clip dragLoop, string decoderPath,
            int width, int height, int fps, int staticClickMs)
            : this(image, idleImage, clickImage, dragImage, idle, click, dragEnter, dragLoop,
                decoderPath, width, height, fps, staticClickMs, 0, 0, 0, 0) { }

        public CharacterPlayer(Image image, string idleImage, string clickImage, string dragImage,
            Clip idle, Clip click, Clip dragEnter, Clip dragLoop, string decoderPath,
            int width, int height, int fps, int staticClickMs,
            int idleFootY, int clickFootY, int dragFootY, int targetFootY) {
            if (image == null) throw new ArgumentNullException("image");
            if (width < 1 || width > 1024 || height < 1 || height > 1024 || fps < 1 || fps > 60)
                throw new ArgumentOutOfRangeException("Frame dimensions or rate");
            if (staticClickMs < 1 || staticClickMs > 30000) throw new ArgumentOutOfRangeException("staticClickMs");
            this.image = image; this.idle = idle; this.click = click;
            this.dragEnter = dragEnter; this.dragLoop = dragLoop; this.decoderPath = decoderPath;
            this.width = width; this.height = height; this.fps = fps; this.staticClickMs = staticClickMs;
            idleStill = new Still(idleImage, width, height, idleFootY, targetFootY);
            clickStill = new Still(clickImage, width, height, clickFootY, targetFootY);
            dragStill = new Still(dragImage, width, height, dragFootY, targetFootY);
            image.Stretch = Stretch.Uniform; LastError = "";
            timer = new DispatcherTimer(DispatcherPriority.Render, image.Dispatcher);
            // Poll faster than the video cadence; Stopwatch decides which frame is due.
            timer.Interval = TimeSpan.FromMilliseconds(8);
            timer.Tick += delegate { Tick(); };
            renderingHandler = delegate { if (!disposed) Tick(); };
            CompositionTarget.Rendering += renderingHandler;
            EnterState("idle"); timer.Start();
        }
        void Verify() {
            image.Dispatcher.VerifyAccess();
            if (disposed) throw new ObjectDisposedException("CharacterPlayer");
        }
        void StopDecoder() {
            try { if (AudioStopRequested != null) AudioStopRequested(this, EventArgs.Empty); }
            catch (Exception e) { LastAudioCallbackError=e.Message; }
            VideoSession old = session; session = null;
            if (old != null) old.Dispose();
            videoBitmap = null;
            heldVideoPixels = null;
            lastPresentedTicks = 0; MaxFrameGapMs = 0;
        }
        void ShowStill() {
            ClearTransition();
            Still still = State == "click" ? clickStill : State == "drag" ? dragStill : idleStill;
            shownPixels = still.Pixels; shownWidth = still.Width; shownHeight = still.Height;
            image.Source = still.Source;
        }
        void ClearTransition() {
            transitionFrom = null; transitionStarted = 0;
        }
        void ArmTransition() {
            if (transitionMs == 0 || !visible || !enabled || shownPixels == null || shownPixels.Length != width*height*4) {
                ClearTransition(); return;
            }
            transitionFrom = (byte[])shownPixels.Clone();
            transitionStarted = 0;
        }
        byte[] BlendFrame(byte[] incoming) {
            if (transitionFrom == null) return incoming;
            long now = Stopwatch.GetTimestamp();
            if (transitionStarted == 0) transitionStarted = now;
            double amount = (now-transitionStarted)*1000.0/Stopwatch.Frequency/Math.Max(1,transitionMs);
            if (amount >= 1) { ClearTransition(); return incoming; }
            amount = amount*amount*(3-2*amount);
            if (transitionBuffer == null) transitionBuffer = new byte[incoming.Length];
            for (int i=0; i<incoming.Length; i+=4) {
                double oldAlpha = transitionFrom[i+3]*(1-amount);
                double newAlpha = incoming[i+3]*amount;
                double alpha = oldAlpha+newAlpha;
                for (int channel=0; channel<3; channel++)
                    transitionBuffer[i+channel] = alpha < .5 ? (byte)0 : (byte)Math.Min(255, Math.Round(
                        (transitionFrom[i+channel]*oldAlpha+incoming[i+channel]*newAlpha)/alpha));
                transitionBuffer[i+3] = (byte)Math.Min(255,Math.Round(alpha));
            }
            BlendedFrameCount++;
            return transitionBuffer;
        }
        void ClearWarmIdle() {
            if (warmIdle != null) warmIdle.Dispose();
            warmIdle = null; warmIdleBitmap = null; warmIdlePixels = null;
        }
        void ClearReadyDrag() {
            if (readyDragLoop != null) readyDragLoop.Dispose();
            readyDragLoop = null;
        }
        bool Play(Clip clip, string nextPhase) {
            StopDecoder(); phase = nextPhase;
            if (clip == null || !clip.Prepared) {
                ShowStill();
                Status = "Static pose preview: video not prepared"; return false;
            }
            if (String.IsNullOrEmpty(clip.Path) || !File.Exists(clip.Path)) {
                Fail("Prepared clip is missing"); return false;
            }
            if (String.IsNullOrEmpty(decoderPath) || !File.Exists(decoderPath)) {
                Fail("FFmpeg executable is unavailable"); return false;
            }
            if (nextPhase == "idle" && warmIdle != null) {
                if (!String.IsNullOrEmpty(warmIdle.Error)) { Fail(warmIdle.Error); return false; }
                session = warmIdle; warmIdle = null;
                videoBitmap = warmIdleBitmap as WriteableBitmap;
                heldVideoPixels = warmIdlePixels;
                if (transitionFrom == null && warmIdleBitmap != null && warmIdlePixels != null) {
                    shownPixels = warmIdlePixels; shownWidth = width; shownHeight = height;
                    image.Source = warmIdleBitmap;
                }
                warmIdleBitmap = null; warmIdlePixels = null;
                session.Resume(); Status = "Playing video: idle"; return true;
            }
            if (nextPhase == "drag-loop" && readyDragLoop != null) {
                if (!String.IsNullOrEmpty(readyDragLoop.Error)) { Fail(readyDragLoop.Error); return false; }
                session = readyDragLoop; readyDragLoop = null;
                session.Resume(); Status = "Loading video: drag-loop"; return true;
            }
            try {
                session = new VideoSession(decoderPath, clip.Path, width, height, fps, clip.Loop);
                if (nextPhase == "drag-enter" && dragLoop != null && dragLoop.Prepared && File.Exists(dragLoop.Path)) {
                    ClearReadyDrag();
                    readyDragLoop = new VideoSession(decoderPath, dragLoop.Path, width, height, fps, true);
                }
                Status = "Loading video: " + phase; return true;
            } catch (Exception e) { Fail(e.Message); return false; }
        }
        void EnterState(string state) {
            ArmTransition();
            if (state == "click") { actionSerial++; clickCueIssued=false; }
            if (state == "drag") { actionSerial++; dragCueIssued=false; }
            if (extraClips.ContainsKey(state)) { actionSerial++; extraCueIssued=false; }
            if (state != "drag") ClearReadyDrag();
            if (state != "idle" && State == "idle" && phase == "idle" && session != null &&
                heldVideoPixels != null && String.IsNullOrEmpty(session.Error) && enabled && visible) {
                ClearWarmIdle(); warmIdle = session; warmIdle.Pause();
                warmIdleBitmap = image.Source as BitmapSource; warmIdlePixels = heldVideoPixels;
                session = null;
            }
            StopDecoder(); State = state;
            bool startsWithVideo = state == "click" ? click != null && click.Prepared :
                (state == "drag" && ((dragEnter != null && dragEnter.Prepared) || (dragLoop != null && dragLoop.Prepared))) || extraClips.ContainsKey(state);
            // Keep the current frame until the new clip is ready. Showing the final
            // click/drag still here caused a visible flash before the first video frame.
            if ((!startsWithVideo && state != "idle") || !enabled || !visible ||
                (state == "idle" && transitionFrom == null)) ShowStill();
            if (!enabled || !visible) { Status = "Static pose: playback paused"; return; }
            if (state == "click") {
                clickDeadline = clock.ElapsedMilliseconds + staticClickMs;
                Play(click, "click");
            } else if (state == "drag") {
                if (dragEnter != null && dragEnter.Prepared && !String.IsNullOrEmpty(dragEnter.Path) && File.Exists(dragEnter.Path))
                    Play(dragEnter, "drag-enter");
                else Play(dragLoop, "drag-loop");
            } else if (extraClips.ContainsKey(state)) Play(extraClips[state],state);
            else Play(idle, "idle");
        }
        void Fail(string error) {
            StopDecoder(); ClearWarmIdle(); ClearReadyDrag(); LastError = error; FailureCount++;
            if (extraClips.ContainsKey(State)) State = "idle";
            ShowStill(); Status = "Static fallback: " + error;
        }
        public bool Click() {
            Verify();
            // Repeated clicks never build a queue; dragging always wins.
            if (!enabled || !visible || State == "drag" || State == "click") return false;
            EnterState("click"); return true;
        }
        public bool BeginDrag() {
            Verify();
            if (!enabled || !visible || State == "drag") return false;
            EnterState("drag"); return true;
        }
        public void EndDrag() {
            Verify();
            if (State != "drag") return;
            if (phase == "drag-loop" && DragReturn != null && DragReturn.Prepared) {
                ArmTransition(); State = "idle";
                Play(DragReturn,"drag-return");
            } else EnterState("idle");
        }
        public void Reset() { Verify(); EnterState("idle"); }
        public void SetVisible(bool value) {
            Verify(); if (visible == value) return; visible = value;
            if (!value) ClearWarmIdle();
            EnterState("idle");
            if (visible && enabled) timer.Start(); else timer.Stop();
        }
        public void SetEnabled(bool value) {
            Verify(); if (enabled == value) return; enabled = value;
            if (!value) ClearWarmIdle();
            EnterState("idle");
            if (visible && enabled) timer.Start(); else timer.Stop();
        }
        public void BindMask(ImageBrush mask) {
            Verify();
            if (mask == null) throw new ArgumentNullException("mask");
            mask.Stretch = Stretch.Uniform;
            BindingOperations.SetBinding(mask, ImageBrush.ImageSourceProperty, new Binding("Source") { Source = image });
        }
        // Input coordinates must be translated into the Image's local space by the host.
        public bool HitTest(double x, double y) {
            Verify();
            if (!visible || shownPixels == null || image.ActualWidth <= 0 || image.ActualHeight <= 0 ||
                Double.IsNaN(x) || Double.IsNaN(y) || Double.IsInfinity(x) || Double.IsInfinity(y)) return false;
            double fit = Math.Min(image.ActualWidth / shownWidth, image.ActualHeight / shownHeight);
            int px = (int)Math.Floor((x - (image.ActualWidth - shownWidth * fit) / 2) / fit);
            int py = (int)Math.Floor((y - (image.ActualHeight - shownHeight * fit) / 2) / fit);
            if (px < 0 || py < 0 || px >= shownWidth || py >= shownHeight) return false;
            return shownPixels[(py * shownWidth + px) * 4 + 3] > 10;
        }
        public void Tick() {
            Verify();
            if (!visible || !enabled) return;
            VideoSession current = session;
            if (current != null) {
                if (!String.IsNullOrEmpty(current.Error)) { Fail(current.Error); return; }
                byte[] pixels;
                if (current.TryTakeDue(out pixels)) {
                    long now = Stopwatch.GetTimestamp();
                    if (lastPresentedTicks != 0)
                        MaxFrameGapMs = Math.Max(MaxFrameGapMs, (now-lastPresentedTicks)*1000.0/Stopwatch.Frequency);
                    lastPresentedTicks = now; RenderedFrameCount++;
                    if (videoBitmap == null) videoBitmap = new WriteableBitmap(width, height, 96, 96, PixelFormats.Bgra32, null);
                    byte[] presented = BlendFrame(pixels);
                    videoBitmap.WritePixels(new Int32Rect(0, 0, width, height), presented, width * 4, 0);
                    current.Recycle(heldVideoPixels); heldVideoPixels = pixels;
                    shownPixels = presented; shownWidth = width; shownHeight = height;
                    image.Source = videoBitmap; Status = "Playing video: " + phase;
                    // Tie the cue to the displayed pose, not to wall-clock time or mouse-down.
                    string cue = null;
                    long index = current.PresentedIndex;
                    if (phase == "click" && !clickCueIssued && index >= (long)Math.Round(fps*0.12)) {
                        clickCueIssued=true; cue="click";
                    }
                    if (!dragCueIssued && ((phase == "drag-enter" && index >= (long)Math.Round(fps*0.12)) || phase == "drag-loop")) {
                        dragCueIssued=true; cue="drag";
                    }
                    if (extraClips.ContainsKey(State) && phase == State && !extraCueIssued && index >= extraCueFrames[State]) {
                        extraCueIssued=true; cue=State;
                    }
                    if (cue != null && SoundCue != null) {
                        try { SoundCue(this, new CharacterSoundCue(cue,actionSerial,index)); }
                        catch (Exception e) { LastAudioCallbackError=e.Message; }
                    }
                } else if (current.Complete && current.PendingFrames == 0) {
                    if (!String.IsNullOrEmpty(current.Error)) { Fail(current.Error); return; }
                    if (current.FrameCount == 0) { Fail("Decoder produced no frames"); return; }
                    if (phase == "drag-enter" && State == "drag") Play(dragLoop, "drag-loop");
                    else if (phase == "drag-return" && State == "idle") EnterState("idle");
                    else if (State == "click" || extraClips.ContainsKey(State)) EnterState("idle");
                    else Fail("Looping decoder stopped unexpectedly");
                    return;
                }
                double timeout = current.FrameCount == 0 ? 5.0 : 2.0;
                if (current.SecondsSinceFrame > timeout) { Fail("Decoder timed out"); return; }
            }
            // The still-image preview is timed; real click videos run to their own EOF.
            if (State == "click" && session == null && clock.ElapsedMilliseconds >= clickDeadline) EnterState("idle");
        }
        public void Dispose() {
            image.Dispatcher.VerifyAccess();
            if (disposed) return;
            disposed = true; timer.Stop(); CompositionTarget.Rendering -= renderingHandler; StopDecoder(); ClearWarmIdle(); ClearReadyDrag(); ClearTransition(); transitionBuffer = null;
        }
    }
}

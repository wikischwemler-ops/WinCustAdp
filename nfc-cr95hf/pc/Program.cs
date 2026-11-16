// CR95HF-Tool: liest NFC-Tags ueber die MB1054A-Bruecke, zeigt sie an und schreibt Aenderungen zurueck.
using System.IO.Ports;
using System.Text;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length > 0) { Test(args); return; }
        ApplicationConfiguration.Initialize(); Application.Run(new MainForm());
    }

    // Kommandozeilentest: Cr95hfTool COM11 [--write]  (Schreibtest aendert einen Nutzerblock und stellt ihn wieder her)
    static void Test(string[] a)
    {
        var portName = a.FirstOrDefault(x => x.StartsWith("COM", StringComparison.OrdinalIgnoreCase)) ?? Cr95hf.FindPort();
        if (portName == null) { Console.WriteLine("MB1054A nicht gefunden"); return; }
        using var d = new Cr95hf(portName); d.Cmd(0xF0);
        Console.WriteLine($"Leser an {portName}: " + d.Idn());
        var t = d.Read(); d.FieldOff();
        if (t == null) { Console.WriteLine("Kein Tag"); return; }
        Console.WriteLine($"{t.Type}  UID {t.Uid}  {t.Blocks.Count} Bloecke a {t.BlockSize} Byte, schreibbar {t.FirstWritable}..{t.LastWritable}");
        for (int i = 0; i < t.Blocks.Count; i++) Console.WriteLine($"{i,3}: {Convert.ToHexString(t.Blocks[i])}");
        if (!a.Contains("--write") || t.LastWritable < t.FirstWritable) return;
        int b = t.LastWritable; var orig = t.Blocks[b]; var test = orig.Select(x => (byte)~x).ToArray();
        bool Step(byte[] data)
        {
            var s = d.Read(); d.WriteBlock(s, b, data); Console.WriteLine("Write-Antwort: " + d.LastWrite);
            var r = d.Read(); d.FieldOff();
            return r != null && r.Blocks[b].SequenceEqual(data);
        }
        Console.WriteLine($"Schreibtest Block {b}: {(Step(test) ? "OK" : "FEHLER")}, Wiederherstellen: {(Step(orig) ? "OK" : "FEHLER")}");
    }
}

class Tag
{
    public string Type = "", Uid = "";
    public int BlockSize = 4, FirstWritable = 0, LastWritable = -1;
    public HashSet<int> Locked = new();   // per Sperrbits dauerhaft schreibgeschuetzt
    public bool CanWrite(int i) => i >= FirstWritable && i <= LastWritable && !Locked.Contains(i);
    public List<byte[]> Blocks = new();
    public bool Is15693;
}

class Cr95hf : IDisposable
{
    readonly SerialPort sp;
    public Cr95hf(string port) { sp = new SerialPort(port, 115200) { ReadTimeout = 1500, DtrEnable = true }; sp.Open(); }
    public void Dispose() => sp.Dispose();

    // Sucht den COM-Port der MB1054A-Bruecke (USB VID 0483 / PID 5740) in der Registry
    public static string FindPort()
    {
        using var k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\USB\VID_0483&PID_5740");
        var present = SerialPort.GetPortNames();
        foreach (var s in k?.GetSubKeyNames() ?? [])
            if (k.OpenSubKey(s + @"\Device Parameters")?.GetValue("PortName") is string p && present.Contains(p)) return p;
        return null;
    }

    public (byte code, byte[] data) Cmd(byte cmd, params byte[] d)
    {
        sp.DiscardInBuffer();
        var f = new byte[d.Length + 2]; f[0] = cmd; f[1] = (byte)d.Length; d.CopyTo(f, 2);
        sp.Write(f, 0, f.Length);
        byte code = (byte)sp.ReadByte(); int len = sp.ReadByte();
        var r = new byte[len]; for (int i = 0; i < len; i++) r[i] = (byte)sp.ReadByte();
        return (code, r);
    }
    (byte, byte[]) Tx(params byte[] d) => Cmd(0x04, d);
    void Proto(params byte[] p) => Cmd(0x02, p);

    public string Idn()
    {
        var (c, d) = Cmd(0x01);
        if (d.Length > 2) d = d[..^2]; // ROM-CRC abschneiden
        return c == 0 ? new string(Encoding.ASCII.GetString(d).Where(ch => ch >= ' ' && ch < 127).ToArray()) : $"Fehler {c:X2}";
    }
    public void FieldOff() => Proto(0x00, 0x00);
    public string LastWrite = "";
    static string Hex(IEnumerable<byte> b) => string.Join(" ", b.Select(x => x.ToString("X2")));

    public Tag Read() => Read15693() ?? Read14443A() ?? Read14443B() ?? ReadFelica();

    // Schnelle Anwesenheitspruefung (ISO 15693 und 14443A): UID oder null
    public string Detect()
    {
        Proto(0x01, 0x0D);
        var (c, r) = Tx(0x26, 0x01, 0x00);
        if (c == 0x80 && r.Length >= 12 && (r[0] & 1) == 0) return Hex(r[2..10].Reverse());
        Proto(0x02, 0x00, 0x01, 0x10, 0x00);
        Cmd(0x09, 0x04, 0x3A, 0x00, 0x58, 0x04); Cmd(0x09, 0x04, 0x68, 0x01, 0x01, 0xD3);
        var u = Select14443A(out _);
        return u == null ? null : Hex(u);
    }

    // ---------- ISO 15693 ----------
    Tag Read15693()
    {
        Proto(0x01, 0x0D);
        var (c, r) = Tx(0x26, 0x01, 0x00);
        if (c != 0x80 || r.Length < 12 || (r[0] & 1) != 0) return null;
        var t = new Tag { Type = "ISO 15693", Is15693 = true, Uid = Hex(r[2..10].Reverse()) };
        int n = 256;
        (c, r) = Tx(0x02, 0x2B);
        if (c == 0x80 && r.Length > 12 && (r[0] & 1) == 0 && (r[1] & 4) != 0)
        {
            int p = 10 + ((r[1] & 1) != 0 ? 1 : 0) + ((r[1] & 2) != 0 ? 1 : 0);
            n = r[p] + 1; t.BlockSize = (r[p + 1] & 0x1F) + 1;
        }
        for (int b = 0; b < n; b++)
        {
            (c, r) = Tx(0x02, 0x20, (byte)b);
            if (c != 0x80 || (r[0] & 1) != 0 || r.Length < t.BlockSize + 4) break;
            t.Blocks.Add(r[1..(1 + t.BlockSize)]);
        }
        t.LastWritable = t.Blocks.Count - 1;
        return t;
    }

    // ---------- ISO 14443A (NTAG / Ultralight; sonst nur UID) ----------
    byte[] Select14443A(out byte sak)
    {
        sak = 0;
        var (c, r) = Tx(0x26, 0x07);
        if (c != 0x80) return null;
        var uid = new List<byte>();
        foreach (byte lvl in new byte[] { 0x93, 0x95, 0x97 })
        {
            (c, r) = Tx(lvl, 0x20, 0x08);
            if (c != 0x80 || r.Length < 5) return null;
            var five = r[..5];
            (c, r) = Tx([lvl, 0x70, .. five, 0x28]);
            if (c != 0x80 || r.Length < 1) return null;
            sak = r[0];
            uid.AddRange(five[0] == 0x88 ? five[1..4] : five[..4]);
            if ((sak & 0x04) == 0) return uid.ToArray();
        }
        return null;
    }
    Tag Read14443A()
    {
        Proto(0x02, 0x00, 0x01, 0x10, 0x00); // Wartezeit FWT = 2^1*(16+1)*128*32/13,56 MHz ~ 10 ms (Schreib-ACK)
        Cmd(0x09, 0x04, 0x3A, 0x00, 0x58, 0x04); Cmd(0x09, 0x04, 0x68, 0x01, 0x01, 0xD3);
        var uid = Select14443A(out byte sak);
        if (uid == null) return null;
        var t = new Tag { Uid = Hex(uid) };
        if (sak == 0x08 || sak == 0x18) { t.Type = "MIFARE Classic (nur UID)"; return t; }
        if ((sak & 0x20) != 0) { t.Type = "ISO 14443A Typ 4 (nur UID)"; return t; }
        int total = 16; t.Type = "Ultralight / Typ 2"; t.LastWritable = 15;
        var (c, r) = Tx(0x60, 0x28);
        if (c == 0x80 && r.Length >= 8)
            (t.Type, total, t.LastWritable) = r[6] switch
            {
                0x0B => ("Ultralight EV1 (48 Byte)", 20, 15), 0x0E => ("Ultralight EV1 (128 Byte)", 41, 35),
                0x0F => ("NTAG213", 45, 39), 0x11 => ("NTAG215", 135, 129), 0x13 => ("NTAG216", 231, 225),
                _ => ($"Typ 2 (Version {Hex(r[..8])})", 16, 15)
            };
        else Select14443A(out _); // nach NAK neu auswaehlen
        for (int p = 0; p < total; p += 4)
        {
            (c, r) = Tx(0x30, (byte)p, 0x28);
            if (c != 0x80 || r.Length < 16) break;
            for (int i = 0; i < 4 && p + i < total; i++) t.Blocks.Add(r[(i * 4)..(i * 4 + 4)]);
        }
        Select14443A(out _); // nach NAK (z. B. geschuetzte Konfigseiten) ist der Tag im Ruhezustand
        t.FirstWritable = 4; t.LastWritable = Math.Min(t.LastWritable, t.Blocks.Count - 1);
        if (t.Blocks.Count > 2) // statische Sperrbytes (Block 2, Byte 2/3): Bit 4-7 -> Seiten 4-7, Byte 3 -> Seiten 8-15
        {
            int l0 = t.Blocks[2][2], l1 = t.Blocks[2][3];
            for (int p = 4; p < 16; p++) if (((p < 8 ? l0 >> p : l1 >> (p - 8)) & 1) != 0) t.Locked.Add(p);
        }
        return t;
    }

    // ---------- ISO 14443B / FeliCa: nur Erkennung ----------
    Tag Read14443B()
    {
        Proto(0x03, 0x01);
        var (c, r) = Tx(0x05, 0x00, 0x00);
        return c == 0x80 && r.Length >= 5 && r[0] == 0x50 ? new Tag { Type = "ISO 14443B (nur PUPI)", Uid = Hex(r[1..5]) } : null;
    }
    Tag ReadFelica()
    {
        Proto(0x04, 0x51);
        var (c, r) = Tx(0x00, 0xFF, 0xFF, 0x00, 0x00);
        return c == 0x80 && r.Length >= 10 ? new Tag { Type = "FeliCa (nur IDm)", Uid = Hex(r[2..10]) } : null;
    }

    // ---------- Schreiben ----------
    public bool WriteBlock(Tag t, int b, byte[] d)
    {
        if (t.Is15693) { var (c, r) = Tx([0x02, 0x21, (byte)b, .. d]); return c == 0x80 && r.Length > 0 && (r[0] & 1) == 0; }
        var (c2, r2) = Tx([0xA2, (byte)b, .. d, 0x28]); // ACK pruefen wir ueber erneutes Lesen
        LastWrite = $"{c2:X2} {Hex(r2)}";
        return true;
    }
}

class MainForm : Form
{
    readonly Button bRead = new() { Text = "Neu lesen", AutoSize = true },
                    bWrite = new() { Text = "Zurückschreiben", AutoSize = true },
                    bSave = new() { Text = "Speichern…", AutoSize = true },
                    bClone = new() { Text = "Klonen aus Datei…", AutoSize = true };
    readonly Label info = new() { AutoSize = true, Padding = new Padding(0, 6, 0, 0) };
    readonly DataGridView grid = new() { Dock = DockStyle.Fill, AllowUserToAddRows = false, RowHeadersVisible = false,
        AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill, Font = new Font("Consolas", 10) };
    Cr95hf dev; Tag tag;
    readonly TagSplash splash = new();
    readonly System.Windows.Forms.Timer poll = new() { Interval = 700 };
    string lastUid; bool busy;

    public MainForm()
    {
        Text = "CR95HF NFC-Tool (MB1054A)"; Width = 720; Height = 600;
        var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 36 };
        top.Controls.AddRange([bRead, bWrite, bSave, bClone, info]);
        grid.Columns.Add("blk", "Block"); grid.Columns.Add("hex", "Hex (editierbar)"); grid.Columns.Add("asc", "ASCII");
        grid.Columns[0].ReadOnly = grid.Columns[2].ReadOnly = true; grid.Columns[0].FillWeight = 15;
        Controls.Add(splash); Controls.Add(grid); Controls.Add(top);
        // Hintergrund-Erkennung: neuer Tag -> automatisch lesen + Animation
        poll.Tick += (_, _) =>
        {
            if (busy) return;
            busy = true;
            try
            {
                if (dev == null) // automatisch (neu) verbinden
                {
                    var p = Cr95hf.FindPort();
                    if (p == null) { info.Text = "MB1054A nicht gefunden – bitte per USB anschließen"; return; }
                    dev = new Cr95hf(p); dev.Cmd(0xF0); info.Text = $"Verbunden ({p}): {dev.Idn()} – Tag auflegen";
                    lastUid = null;
                }
                var u = dev.Detect(); dev.FieldOff();
                if (u != null && u != lastUid) { ReadTag(); if (tag != null) splash.Play(tag.Type, "UID " + tag.Uid); }
                else if (u == null && lastUid != null) info.Text = "Kein Tag – bitte auflegen";
                lastUid = u;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException)
            { dev?.Dispose(); dev = null; info.Text = "Verbindung getrennt – warte auf MB1054A"; } // Board abgezogen
            catch (TimeoutException) { }
            finally { busy = false; }
        };
        poll.Start();
        bRead.Click += (_, _) => Run(ReadTag);
        bWrite.Click += (_, _) => Run(WriteTag);
        bSave.Click += (_, _) => Run(SaveTag);
        bClone.Click += (_, _) => Run(CloneFromFile);
    }

    void Run(Action a)
    {
        busy = true;
        try { a(); } catch (Exception e) { info.Text = "Fehler: " + e.Message; }
        finally { busy = false; }
    }

    void ReadTag()
    {
        tag = dev.Read(); dev.FieldOff(); grid.Rows.Clear();
        if (tag == null) { info.Text = "Kein Tag gefunden"; return; }
        info.Text = $"{tag.Type}  UID {tag.Uid}  {tag.Blocks.Count} Blöcke à {tag.BlockSize} Byte";
        for (int i = 0; i < tag.Blocks.Count; i++)
        {
            var b = tag.Blocks[i];
            int r = grid.Rows.Add(i.ToString(), string.Join(" ", b.Select(x => x.ToString("X2"))),
                new string(b.Select(x => x is >= 32 and < 127 ? (char)x : '.').ToArray()));
            if (!tag.CanWrite(i)) { grid.Rows[r].ReadOnly = true; grid.Rows[r].DefaultCellStyle.ForeColor = Color.Gray; }
        }
    }

    void WriteTag()
    {
        if (tag == null || tag.Blocks.Count == 0) { info.Text = "Erst einen beschreibbaren Tag lesen"; return; }
        var changes = new List<(int, byte[])>();
        for (int i = tag.FirstWritable; i <= tag.LastWritable; i++)
        { if (!tag.CanWrite(i)) continue;
            var d = ((string)grid.Rows[i].Cells[1].Value).Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(s => Convert.ToByte(s, 16)).ToArray();
            if (d.Length != tag.BlockSize) throw new Exception($"Block {i}: {tag.BlockSize} Bytes erwartet");
            if (!d.SequenceEqual(tag.Blocks[i])) changes.Add((i, d));
        }
        WriteChanges(changes, $"{changes.Count} Block/Blöcke auf den Tag schreiben?");
    }

    // Aktuellen Tag als Textdatei sichern (Zeile "# Typ UID", dann "Block:HEX")
    void SaveTag()
    {
        if (tag == null || tag.Blocks.Count == 0) { info.Text = "Erst einen Tag auflegen"; return; }
        using var d = new SaveFileDialog { Filter = "NFC-Abbild (*.nfc)|*.nfc", FileName = tag.Uid.Replace(" ", "") + ".nfc" };
        if (d.ShowDialog() != DialogResult.OK) return;
        File.WriteAllLines(d.FileName, [$"# {tag.Type} | UID {tag.Uid}", .. tag.Blocks.Select((b, i) => $"{i}:{Convert.ToHexString(b)}")]);
        info.Text = "Gespeichert: " + Path.GetFileName(d.FileName);
    }

    // Gespeichertes Abbild auf den aufliegenden Tag schreiben (nur dessen beschreibbare Bloecke; UID bleibt)
    void CloneFromFile()
    {
        if (tag == null || tag.LastWritable < tag.FirstWritable) { info.Text = "Erst einen beschreibbaren Ziel-Tag auflegen"; return; }
        using var d = new OpenFileDialog { Filter = "NFC-Abbild (*.nfc)|*.nfc" };
        if (d.ShowDialog() != DialogResult.OK) return;
        var lines = File.ReadAllLines(d.FileName);
        var head = lines.FirstOrDefault(l => l.StartsWith('#'))?.TrimStart('#', ' ') ?? "?";
        var src = lines.Where(l => !l.StartsWith('#') && l.Contains(':')).Select(l => l.Split(':'))
                       .ToDictionary(p => int.Parse(p[0]), p => Convert.FromHexString(p[1].Trim()));
        var changes = new List<(int, byte[])>();
        for (int i = tag.FirstWritable; i <= tag.LastWritable; i++)
            if (tag.CanWrite(i) && src.TryGetValue(i, out var b) && b.Length == tag.BlockSize) changes.Add((i, b));
        int lost = src.Keys.Count(k => k > tag.LastWritable && src[k].Any(x => x != 0));
        WriteChanges(changes, $"Quelle: {head}\nZiel: {tag.Type} | UID {tag.Uid}\n\n{changes.Count} Blöcke schreiben?" + (tag.Locked.Count > 0 ? $" ({tag.Locked.Count} gesperrte Blöcke werden übersprungen)" : "") +
            (lost > 0 ? $"\n\nAchtung: {lost} Quellblöcke mit Daten passen nicht auf den Ziel-Tag." : "") +
            "\nUID und Konfiguration des Ziel-Tags bleiben unverändert.");
    }

    void WriteChanges(List<(int, byte[])> changes, string question)
    {
        if (changes.Count == 0) { info.Text = "Keine Änderungen"; return; }
        if (MessageBox.Show(question, "Schreiben", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
        var uid = tag.Uid;
        var again = dev.Read(); // Tag neu auswaehlen
        if (again == null || again.Uid != uid) { dev.FieldOff(); info.Text = "Tag nicht mehr da oder anderer Tag"; return; }
        int ok = changes.Count(ch => dev.WriteBlock(again, ch.Item1, ch.Item2));
        ReadTag();
        int verified = changes.Count(ch => tag != null && ch.Item1 < tag.Blocks.Count && tag.Blocks[ch.Item1].SequenceEqual(ch.Item2));
        info.Text = $"Geschrieben und geprüft: {verified}/{changes.Count}" + (tag == null ? " (Tag weg)" : "  " + info.Text);
    }
}

// Einblendung beim Auflegen eines Tags: pulsierende Funkringe, Typ und UID, blendet nach ~2 s aus
class TagSplash : Control
{
    readonly System.Windows.Forms.Timer t = new() { Interval = 30 };
    readonly Font big = new("Segoe UI", 14, FontStyle.Bold), small = new("Segoe UI", 10);
    int frame; string title = "", sub = "";

    public TagSplash()
    {
        DoubleBuffered = true; Visible = false; Size = new Size(360, 220);
        t.Tick += (_, _) => { if (++frame > 70) { t.Stop(); Visible = false; } Invalidate(); };
    }

    public void Play(string a, string b)
    {
        title = a; sub = b; frame = 0;
        Location = new Point((Parent.ClientSize.Width - Width) / 2, (Parent.ClientSize.Height - Height) / 2);
        Visible = true; BringToFront(); t.Start();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics; g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.Clear(Color.FromArgb(32, 36, 48));
        float cx = Width / 2f, cy = 80;
        for (int i = 0; i < 3; i++)
        {
            float r = ((frame + i * 12) % 36) * 2f + 10;
            using var p = new Pen(Color.FromArgb(Math.Max(0, 255 - (int)(r * 3.4)), 80, 200, 255), 3);
            g.DrawEllipse(p, cx - r, cy - r, 2 * r, 2 * r);
        }
        using (var b = new SolidBrush(Color.FromArgb(80, 200, 255))) g.FillEllipse(b, cx - 12, cy - 12, 24, 24);
        TextRenderer.DrawText(g, "Tag erkannt: " + title, big, new Rectangle(0, 140, Width, 30), Color.White, TextFormatFlags.HorizontalCenter);
        TextRenderer.DrawText(g, sub, small, new Rectangle(0, 178, Width, 24), Color.Silver, TextFormatFlags.HorizontalCenter);
    }
}

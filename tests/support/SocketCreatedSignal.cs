using System;
using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace LibTmux.Testing;

// Completes when the owned tmux server creates its socket. inotify reports the
// socket on Linux; FSEvents never does on macOS, so macOS watches the directory
// with kqueue, whose NOTE_WRITE fires when bind() adds the entry.
public sealed class SocketCreatedSignal : IDisposable
{
    private const short EvfiltRead = -1;
    private const short EvfiltVnode = -4;
    private const ushort EvAdd = 0x0001;
    private const ushort EvClear = 0x0020;
    private const uint NoteWrite = 0x00000002;
    private const int OEvtonly = 0x00008000;

    private readonly string socketPath;
    private readonly FileSystemWatcher watcher;
    private readonly Thread kqueueThread;
    private readonly int kqueueFd = -1;
    private readonly int directoryFd = -1;
    private readonly int[] wakePipe = { -1, -1 };
    private readonly TaskCompletionSource<bool> signal =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int createdEvents;
    private int errorEvents;

    public SocketCreatedSignal(string directory)
    {
        socketPath = Path.Combine(directory, "socket");
        if (OperatingSystem.IsMacOS())
        {
            directoryFd = open(directory, OEvtonly);
            kqueueFd = directoryFd < 0 ? -1 : kqueue();
            if (kqueueFd < 0 || pipe(wakePipe) < 0)
                throw new IOException($"kqueue watch failed ({Marshal.GetLastPInvokeError()}).");
            // Dispose writes to the pipe, which wakes the watching thread.
            KEvent[] changes =
            {
                new() { Ident = (nuint)directoryFd, Filter = EvfiltVnode, Flags = EvAdd | EvClear, Fflags = NoteWrite },
                new() { Ident = (nuint)wakePipe[0], Filter = EvfiltRead, Flags = EvAdd },
            };
            if (kevent(kqueueFd, changes, changes.Length, null, 0, IntPtr.Zero) < 0)
                throw new IOException($"kqueue registration failed ({Marshal.GetLastPInvokeError()}).");
            kqueueThread = new Thread(WatchDirectory) { IsBackground = true, Name = "socket kqueue" };
            kqueueThread.Start();
        }
        else
        {
            watcher = new FileSystemWatcher(directory, "socket");
            watcher.Created += (_, _) =>
            {
                Interlocked.Increment(ref createdEvents);
                signal.TrySetResult(true);
            };
            watcher.Error += (_, e) =>
            {
                Interlocked.Increment(ref errorEvents);
                signal.TrySetException(e.GetException());
            };
            watcher.EnableRaisingEvents = true;
        }
    }

    public Task Ready => signal.Task;

    public int CreatedEvents => Volatile.Read(ref createdEvents);

    public int ErrorEvents => Volatile.Read(ref errorEvents);

    // bind() creates the socket just before listen() accepts connections, and
    // nothing reports listen(), so yield across that window. A refused connect
    // after the server exits or stays unbound is a failure, not a retry.
    public static bool WaitListening(string path, Process server)
    {
        for (int attempt = 0; attempt < 1000; attempt++)
        {
            if (server.HasExited) return false;
            using Socket probe = new(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            try
            {
                probe.Connect(new UnixDomainSocketEndPoint(path));
                return true;
            }
            catch (SocketException e) when (e.SocketErrorCode == SocketError.ConnectionRefused)
            {
                Thread.Yield();
            }
        }
        return false;
    }

    private void WatchDirectory()
    {
        KEvent[] events = new KEvent[1];
        try
        {
            // Subscribed before this check, so a socket created first is not lost.
            while (!File.Exists(socketPath))
            {
                if (kevent(kqueueFd, null, 0, events, 1, IntPtr.Zero) < 0)
                {
                    int error = Marshal.GetLastPInvokeError();
                    if (error == 4) continue;
                    throw new IOException($"kqueue wait failed ({error}).");
                }
                if (events[0].Filter == EvfiltRead) return;
            }
            Interlocked.Increment(ref createdEvents);
            signal.TrySetResult(true);
        }
        catch (Exception e)
        {
            Interlocked.Increment(ref errorEvents);
            signal.TrySetException(e);
        }
    }

    public void Dispose()
    {
        watcher?.Dispose();
        if (kqueueThread is null) return;
        _ = write(wakePipe[1], new byte[1], 1);
        kqueueThread.Join();
        _ = close(kqueueFd);
        _ = close(directoryFd);
        _ = close(wakePipe[0]);
        _ = close(wakePipe[1]);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEvent
    {
        public nuint Ident;
        public short Filter;
        public ushort Flags;
        public uint Fflags;
        public nint Data;
        public IntPtr Udata;
    }

    [DllImport("libc", SetLastError = true)]
    private static extern int kqueue();

    [DllImport("libc", SetLastError = true)]
    private static extern int kevent(int kq, KEvent[] changelist, int nchanges, [Out] KEvent[] eventlist, int nevents, IntPtr timeout);

    [DllImport("libc", SetLastError = true)]
    private static extern int open([MarshalAs(UnmanagedType.LPUTF8Str)] string path, int flags);

    [DllImport("libc", SetLastError = true)]
    private static extern int close(int fd);

    [DllImport("libc", SetLastError = true)]
    private static extern int pipe(int[] fds);

    [DllImport("libc", SetLastError = true)]
    private static extern nint write(int fd, byte[] buffer, nint count);
}

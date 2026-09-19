using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace LibTmux.Testing;

public static class OwnedDaemonReaper
{
    private const int SetChildSubreaper = 36;
    private const int Interrupted = 4;
    private const int NoChild = 10;
    private const int NoProcess = 3;

    public static void Enable()
    {
        if (OperatingSystem.IsLinux() && Prctl(SetChildSubreaper, 1, 0, 0, 0) != 0)
        {
            throw new Win32Exception(Marshal.GetLastPInvokeError(), "Cannot own detached tmux descendants.");
        }
    }

    public static void Reap(Process process)
    {
        if (!OperatingSystem.IsLinux())
        {
            if (!process.WaitForExit(1000))
            {
                throw new TimeoutException("Owned tmux process did not exit.");
            }

            return;
        }

        // Only the registered daemon or pane PID can be reaped. Other .NET
        // subprocesses retain their normal Process ownership and wait handles.
        int processId = process.Id;
        Task wait = Task.Run(() => ReapChild(processId));
        try
        {
            wait.WaitAsync(TimeSpan.FromSeconds(1)).GetAwaiter().GetResult();
        }
        catch (TimeoutException)
        {
            process.Kill(entireProcessTree: true);
            wait.WaitAsync(TimeSpan.FromSeconds(1)).GetAwaiter().GetResult();
            throw;
        }
    }

    private static void ReapChild(int processId)
    {
        int result;
        do
        {
            result = WaitPid(processId, out _, 0);
        }
        while (result < 0 && Marshal.GetLastPInvokeError() == Interrupted);

        if (result == processId)
        {
            return;
        }

        int error = Marshal.GetLastPInvokeError();
        // tmux may have reaped its pane before exiting; absence is the only
        // acceptable ECHILD case. A live unowned process is never claimed.
        if (error == NoChild && Kill(processId, 0) < 0 && Marshal.GetLastPInvokeError() == NoProcess)
        {
            return;
        }

        throw new Win32Exception(error, "Owned tmux process could not be reaped.");
    }

    [DllImport("libc", EntryPoint = "prctl", SetLastError = true)]
    private static extern int Prctl(int option, ulong argument2, ulong argument3, ulong argument4, ulong argument5);

    [DllImport("libc", EntryPoint = "waitpid", SetLastError = true)]
    private static extern int WaitPid(int processId, out int status, int options);

    [DllImport("libc", EntryPoint = "kill", SetLastError = true)]
    private static extern int Kill(int processId, int signal);
}

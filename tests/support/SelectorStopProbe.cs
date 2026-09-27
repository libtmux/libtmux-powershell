using System;
using System.Reflection;
using System.Threading;

namespace LibTmux.Testing;

public static class SelectorStopProbe
{
    public static bool RetainedMatchIsSuppressed(Type cmdletType, object pane)
    {
        Type selectorType = cmdletType.Assembly.GetType("LibTmux.PowerShell.QuerySelection`1", true)!
            .MakeGenericType(pane.GetType());
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        ConstructorInfo constructor = selectorType.GetConstructors(flags)[0];
        object target = Enum.Parse(constructor.GetParameters()[0].ParameterType, "Pane");
        object selector = constructor.Invoke([target]);
        selectorType.GetField("retained", flags)!.SetValue(selector, pane);
        selectorType.GetField("exactlyOne", flags)!.SetValue(selector, true);
        int writes = 0;
        object[] arguments =
        [
            new Action<object>(_ => writes++),
            new Action<object>(_ => throw new InvalidOperationException("Unexpected selector error.")),
            new Func<bool>(() => true),
            CancellationToken.None,
        ];
        try
        {
            selectorType.GetMethod("Complete", flags)!.Invoke(selector, arguments);
            return false;
        }
        catch (TargetInvocationException exception) when (
            exception.InnerException?.GetType().FullName == "System.Management.Automation.PipelineStoppedException")
        {
            return writes == 0;
        }
    }
}

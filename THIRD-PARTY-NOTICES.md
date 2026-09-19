# Third-party dependencies

Local artifacts bundle the dependencies listed in each module's
`dependencies.json`. The following upstream licenses apply:

- [LibTmux and LibTmux.Workspace: MIT](https://github.com/libtmux/libtmux-dotnet/blob/master/LICENSE).
- [Microsoft.Extensions.Logging.Abstractions and Microsoft.Extensions.DependencyInjection.Abstractions: MIT](https://github.com/dotnet/runtime/blob/5535e31a712343a63f5d7d796cd874e563e5ac14/LICENSE.TXT).
- [YamlDotNet: MIT](https://github.com/aaubry/YamlDotNet/blob/748334a8fa7c227740018b284b71ad95cc6b7fc7/LICENSE.txt).

The package build includes their license texts under `licenses/`.
PowerShell supplies `System.Management.Automation`; its implementation and
the PowerShell runtime are not included in these modules.

# Copy HM store symlinks to writable files so editors / p10k can save on startup.
{
  hmLib,
  lib,
  pkgs,
}:
paths:
hmLib.hm.dag.entryAfter [ "writeBoundary" ] ''
  ${lib.concatMapStrings (
    settingsPath:
    let
      escaped = lib.escapeShellArg settingsPath;
    in
    ''
      settingsPath=${escaped}
      if [ -L "$settingsPath" ]; then
        ${pkgs.coreutils}/bin/install -m 0644 "$(${pkgs.coreutils}/bin/readlink "$settingsPath")" "$settingsPath"
      fi
    ''
  ) paths}
''

# Resolve package attributes with consistent error messages.
{ lib }:
{
  # resolvePkg pkgs "system package" "git"
  resolvePkg =
    pkgs: label: name:
    if !lib.hasAttr name pkgs then
      throw "Unknown ${label} in config: ${name}"
    else
      pkgs.${name};

  # resolveAttr set "nerd font" "meslo-lg"
  resolveAttr =
    set: label: name:
    if !lib.hasAttr name set then
      throw "Unknown ${label} in config: ${name}"
    else
      set.${name};
}

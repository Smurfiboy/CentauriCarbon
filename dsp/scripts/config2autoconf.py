#!/usr/bin/env python3
"""Convert a Linux-style .config file to a C autoconf.h header.

Usage: config2autoconf.py <.config> <autoconf.h>

This is used instead of kconfiglib/genconfig.py because the full
Allwinner R528 DSP Kconfig hierarchy is not included in this repository.
"""

import re
import sys


def config_to_autoconf(config_path, out_path):
    with open(config_path, encoding='utf-8') as f:
        lines = f.readlines()

    with open(out_path, 'w', encoding='utf-8') as out:
        out.write("/* Automatically generated from .config — DO NOT EDIT. */\n")
        out.write("#ifndef AUTOCONF_H\n")
        out.write("#define AUTOCONF_H\n\n")

        for line in lines:
            line = line.rstrip()

            # Blank lines
            if not line:
                continue

            # Comment lines — check for "not set" markers
            if line.startswith('#'):
                m = re.match(r'^# (CONFIG_\S+) is not set$', line)
                if m:
                    out.write(f"/* {m.group(1)} is not set */\n")
                continue

            # CONFIG_FOO=y
            m = re.match(r'^(CONFIG_\S+)=y$', line)
            if m:
                out.write(f"#define {m.group(1)} 1\n")
                continue

            # CONFIG_FOO=n  (explicitly disabled)
            m = re.match(r'^(CONFIG_\S+)=n$', line)
            if m:
                out.write(f"/* {m.group(1)} is not set */\n")
                continue

            # CONFIG_FOO="string value"
            m = re.match(r'^(CONFIG_\S+)=(".*")$', line)
            if m:
                out.write(f"#define {m.group(1)} {m.group(2)}\n")
                continue

            # CONFIG_FOO=integer (decimal or hex)
            m = re.match(r'^(CONFIG_\S+)=(0x[0-9a-fA-F]+|\d+)$', line)
            if m:
                out.write(f"#define {m.group(1)} {m.group(2)}\n")
                continue

        out.write("\n#endif /* AUTOCONF_H */\n")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <.config> <autoconf.h>", file=sys.stderr)
        sys.exit(1)
    config_to_autoconf(sys.argv[1], sys.argv[2])

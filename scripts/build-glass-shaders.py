#!/usr/bin/env python3
"""Build all geometry and uniform adapters from the one shared Liquid Glass source."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMON = Path('config/quickshell/Common')
SOURCE = COMMON / 'LiquidGlass.frag'
VARIANTS = {
    'LiquidGlass.frag.qsb': (),
    'LiquidGlass.frag.dock.qsb': ('DOCK_THIN_BORDER',),
    'LiquidGlass-bar.frag.qsb': ('GLASS_BAR',),
    'LiquidGlass-control-center.frag.qsb': ('GLASS_BAR', 'CONTROL_CENTER'),
    'LiquidGlass-frosted-menu.frag.qsb': ('GLASS_BAR', 'FROSTED_MENU'),
    'LiquidGlass-lock.frag.qsb': ('GLASS_LOCK',),
    'LiquidGlass-menu.frag.qsb': ('GLASS_MENU',),
    'LiquidGlass-tooltip.frag.qsb': ('DOCK_TOOLTIP', 'DOCK_THIN_BORDER'),
    'LiquidGlass-portal.frag.qsb': ('GLASS_PORTAL',),
    'LiquidGlass-notch.frag.qsb': ('GLASS_NOTCH',),
    'LiquidGlass-slider.frag.qsb': ('GLASS_SLIDER',),
    'LiquidGlass-text.frag.qsb': ('GLASS_TEXT',),
    'LiquidGlass-coat.frag.qsb': ('GLASS_COAT',),
    'LiquidGlass-voice.frag.qsb': ('GLASS_VOICE',),
    'LiquidGlass-spotlight.frag.qsb': ('SPOTLIGHT_BORDER_ONLY',),
    'LiquidGlass-spotlight-gooey.frag.qsb': ('SPOTLIGHT_GOOEY', 'SPOTLIGHT_BORDER_ONLY'),
    'LiquidGlass-luma.frag.qsb': ('LUMA_GOOEY',),
}


def shader_jobs():
    return {COMMON / name: (SOURCE, defines) for name, defines in VARIANTS.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--qsb', help='Qt 6 Shader Baker executable')
    args = parser.parse_args()
    qsb = args.qsb or next((str(p) for p in (
        shutil.which('qsb'), shutil.which('qsb6'), '/usr/lib/qt6/bin/qsb',
        '/usr/lib64/qt6/bin/qsb', '/usr/lib/qt/bin/qsb') if p and Path(p).is_file()), None)
    if not qsb:
        parser.error('Qt 6 qsb is required (qt6-shadertools).')
    # Validate every adapter before replacing any installed build artifact.
    with tempfile.TemporaryDirectory(prefix='macshell-shared-glass-') as temporary:
        for name, defines in VARIANTS.items():
            command = [qsb, '--qt6']
            for define in defines:
                command += ['-D', define]
            subprocess.run(command + ['-o', str(Path(temporary) / name), str(ROOT / SOURCE)], check=True)
        for name in VARIANTS:
            shutil.copyfile(Path(temporary) / name, ROOT / COMMON / name)
        # SDDM is deployed separately. Only generated binaries are duplicated;
        # its theme never owns another copy of the material source.
        greeter = ROOT / 'extras/sddm/theme'
        for name, variant in (('liquidglass.frag.qsb', 'LiquidGlass-lock.frag.qsb'),
                              ('glasstext.frag.qsb', 'LiquidGlass-text.frag.qsb')):
            shutil.copyfile(Path(temporary) / variant, greeter / name)
    print(f'Built {len(VARIANTS)} adapters from {SOURCE}; updated 2 SDDM bundles.')


if __name__ == '__main__':
    main()

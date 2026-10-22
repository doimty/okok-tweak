#!/usr/bin/env python3
"""Stable CI entry point; supersedes the old CGImage/post-tint model.
The previous model is historical only. This runner uses actual production source
plus independent factory/parameter tests, and preserves exit77 on non-macOS.
"""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('run_svg_parameter_native.py')),run_name='__main__')

"""Minimal stand-in for the parts of anadama2 that biobakery_workflows imports.

The vis and stats workflows no longer use the AnADAMA2 workflow framework, but
biobakery_workflows -- whose utilities, visualizations and files modules the
report still relies on -- imports anadama2 at module scope:

    biobakery_workflows/utilities.py:35   from anadama2.tracked import TrackedDirectory
    biobakery_workflows/files.py:30       from anadama2 import reporters

Only those few names are ever touched on the code paths the reports use, so
this package supplies them and nothing else. It is placed at the front of
sys.path by the report drivers, which means the real anadama2 is never
imported even when it happens to be installed -- no workflow engine, no
task database, no leveldb.

If biobakery_workflows ever reaches for something not defined here it will
raise ImportError or AttributeError rather than silently misbehave, which is
the intended failure mode.
"""

from . import helpers
from . import reporters
from . import tracked

from .document import PweaveDocument
from .tracked import TrackedDirectory

__all__ = ["helpers", "reporters", "tracked", "PweaveDocument", "TrackedDirectory", "Task"]


class Task(object):
    """ Placeholder; nothing in the report path constructs AnADAMA tasks """

    def __init__(self, *args, **kwargs):
        raise NotImplementedError(
            "AnADAMA2 tasks are not available: this workflow runs under Nextflow.")

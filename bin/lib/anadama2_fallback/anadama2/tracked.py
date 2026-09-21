"""Stand-in for anadama2.tracked.

biobakery_workflows.utilities imports TrackedDirectory at module scope, but only
uses it inside the 16s workflow-building helpers, which Nextflow replaces. This
keeps the import working and records the path, without any dependency tracking.
"""

import os


class TrackedDirectory(object):
    """ A directory path; dependency tracking is Nextflow's job here """

    def __init__(self, name):
        self.name = name

    def exists(self):
        return os.path.isdir(self.name)

    def __str__(self):
        return str(self.name)

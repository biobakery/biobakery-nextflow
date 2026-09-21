"""Stand-in for anadama2.reporters.

biobakery_workflows.files uses LOG_FILE_NAME to locate the workflow log in an
output folder, and workflow_info.pmd reads versions and commands out of it.
The log parsing lives in biobakery_log so it is shared with the templates.
"""

from biobakery_log import LoggerReporter, SHELL_COMMAND, VERSION_COMMAND

# the log file name biobakery_workflows searches an output folder for
LOG_FILE_NAME = "anadama.log"

__all__ = ["LoggerReporter", "LOG_FILE_NAME", "SHELL_COMMAND", "VERSION_COMMAND"]

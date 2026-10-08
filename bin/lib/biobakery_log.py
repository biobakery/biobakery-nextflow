"""Read software versions and commands out of a workflow log.

Replaces anadama2.reporters.LoggerReporter.read_log(), which workflow_info.pmd
uses to fill in the "Data Processing Workflow Information" section, so the
report renders without the AnADAMA2 workflow framework installed.

The "commands" and "versions" branches are ported verbatim -- the vis workflow
is normally pointed at a folder produced by `biobakery_workflows`, so the log it
finds there is in the AnADAMA format and must still parse. The "benchmarking"
and "variables" branches are not ported: workflow_info.pmd never asks for them.

anadama2 is distributed under the MIT license; see LICENSE-anadama2.
"""

import collections
import os

# the log line prefixes AnADAMA writes, from anadama2.reporters
SHELL_COMMAND = "Executing with shell: "
VERSION_COMMAND = "Tracked executable version: "


class LoggerReporter(object):
    """ The read_log interface workflow_info.pmd expects """

    @classmethod
    def read_log(cls, file, type, remove_paths=True):
        """ Read the data from the log file """

        data = collections.OrderedDict()
        with open(file) as file_handle:
            lines = file_handle.readlines()

        if type == "commands":
            for line in lines:
                if SHELL_COMMAND in line:
                    new_command = line.split(SHELL_COMMAND)[-1].strip()
                    if remove_paths:
                        # show the executable names rather than full paths
                        new_command = " ".join(
                            [os.path.split(i.rstrip(os.path.sep))[-1]
                             for i in new_command.split(" ")])
                    data[new_command] = 1
        else:
            # versions; drop the redundant wording, these are already labelled
            def format_output(value):
                return value.replace("Version:", "").replace(", version", "").split("/")[-1]

            for line in lines:
                if VERSION_COMMAND in line:
                    data[format_output(line.split(VERSION_COMMAND)[-1].strip())] = 1

        log_info = list(data.keys())

        if not log_info:
            log_info = ["No {} found in log".format(type)]

        return log_info

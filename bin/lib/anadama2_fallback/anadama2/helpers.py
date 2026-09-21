"""Stand-in for anadama2.helpers.

biobakery_workflows.utilities imports sh and format_command inside run_task(),
which builds and runs an AnADAMA command outside of a workflow. The report path
does not call it -- the tasks that used it are Nextflow processes now -- so
these raise rather than half-working.
"""


def sh(s, log_command=True, **kwargs):
    raise NotImplementedError(
        "anadama2.helpers.sh is not available: commands run as Nextflow processes.")


def format_command(command, depends=None, targets=None, **kwargs):
    raise NotImplementedError(
        "anadama2.helpers.format_command is not available: commands run as "
        "Nextflow processes.")
